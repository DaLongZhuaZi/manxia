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
import { ErrorRecordManager, ErrorRecord, ErrorSource, ErrorSummary, TagCount, CategoryCount } from '../../Framework/Debug/ErrorRecordManager';
import { getErrorMonitorService } from '../../Framework/Debug/ErrorMonitorService';
import { getCrashRecorderService } from '../../Framework/Debug/CrashRecorderService';
import { DownloadDirManager } from '../../Framework/Storage/DownloadDirManager';

const TAG = 'ErrorManagementSubPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

/** 过滤类型 */
type FilterType = 'all' | 'runtime' | 'crash' | 'network';
type CategoryFilterType = 'all' | 'network' | 'download' | 'storage' | 'data' | 'parser' | 'source' | 'webview' | 'auth' | 'sync' | 'ui' | 'system' | 'unknown';

class KnownLogDirs {
  errorLogsDir: string = '';
  crashLogsDir: string = '';
  downloadLogsDir: string = '';
}

class DeleteExecutionStats {
  mode: string = 'range';
  targetedRecords: number = 0;
  targetedLogFileNames: number = 0;
  attemptedDeletes: number = 0;
  successfulDeletes: number = 0;
  failedDeletes: number = 0;
  errorLogsAttempts: number = 0;
  crashLogsAttempts: number = 0;
  downloadLogsAttempts: number = 0;
  residualAttempts: number = 0;
  failedSamples: string[] = [];
}

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
  @State summary: ErrorSummary = { total: 0, runtimeErrors: 0, crashes: 0, networkErrors: 0, categoryCounts: [], topTags: [], firstTime: 0, lastTime: 0 };
  @State filterType: FilterType = 'all';
  @State categoryFilterType: CategoryFilterType = 'all';
  @State searchText: string = '';

  // 多选
  @State isSelectMode: boolean = false;
  @State selectedIds: string[] = [];

  // 导出状态
  @State isExporting: boolean = false;

  // 详情展开
  @State expandedId: string = '';
  @State recordsListOpacity: number = 1;
  @State recordsListScale: number = 1;
  @State showClearRangePanel: boolean = false;
  @State clearPanelOpacity: number = 0;
  @State clearPanelScale: number = 0.92;
  @State clearRangeMinTime: number = 0;
  @State clearRangeMaxTime: number = 0;
  @State clearRangeStartPercent: number = 0;
  @State clearRangeEndPercent: number = 100;
  @State clearRangeStartTime: number = 0;
  @State clearRangeEndTime: number = 0;
  @State clearRangeSelectedCount: number = 0;
  @State isClearing: boolean = false;
  private clearPanelCloseTimer: number = -1;

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
    if (this.clearPanelCloseTimer >= 0) {
      clearTimeout(this.clearPanelCloseTimer);
      this.clearPanelCloseTimer = -1;
    }
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

    if (this.categoryFilterType !== 'all') {
      records = records.filter((r: ErrorRecord) => this.getRecordCategory(r) === this.categoryFilterType);
    }

    if (this.searchText.length > 0) {
      const kw = this.searchText.toLowerCase();
      records = records.filter((r: ErrorRecord) =>
        r.message.toLowerCase().includes(kw) ||
        r.tag.toLowerCase().includes(kw) ||
        r.timeStr.includes(kw) ||
        this.getCategoryLabel(this.getRecordCategory(r)).toLowerCase().includes(kw)
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
    this.openClearRangePanel();
  }

  private openClearRangePanel(): void {
    if (this.allRecords.length === 0 || this.isClearing) {
      return;
    }
    if (this.clearPanelCloseTimer >= 0) {
      clearTimeout(this.clearPanelCloseTimer);
      this.clearPanelCloseTimer = -1;
    }
    let minTime = Number.MAX_SAFE_INTEGER;
    let maxTime = 0;
    for (let i = 0; i < this.allRecords.length; i++) {
      const ts = this.allRecords[i].timestamp;
      if (ts < minTime) {
        minTime = ts;
      }
      if (ts > maxTime) {
        maxTime = ts;
      }
    }
    if (minTime === Number.MAX_SAFE_INTEGER) {
      return;
    }
    if (minTime >= maxTime) {
      const padding = 60 * 1000;
      minTime = Math.max(0, minTime - padding);
      maxTime = maxTime + padding;
    }
    this.clearRangeMinTime = minTime;
    this.clearRangeMaxTime = maxTime;
    this.clearRangeStartPercent = 0;
    this.clearRangeEndPercent = 100;
    this.clearRangeStartTime = minTime;
    this.clearRangeEndTime = maxTime;
    this.clearRangeSelectedCount = this.allRecords.length;
    this.showClearRangePanel = true;
    this.clearPanelOpacity = 0;
    this.clearPanelScale = 0.92;
    animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.clearPanelOpacity = 1;
      this.clearPanelScale = 1;
    });
  }

  private closeClearRangePanel(): void {
    if (this.clearPanelCloseTimer >= 0) {
      clearTimeout(this.clearPanelCloseTimer);
      this.clearPanelCloseTimer = -1;
    }
    animateTo({ duration: 180, curve: Curve.EaseIn }, () => {
      this.clearPanelOpacity = 0;
      this.clearPanelScale = 0.92;
    });
    this.clearPanelCloseTimer = setTimeout(() => {
      this.showClearRangePanel = false;
      this.clearPanelCloseTimer = -1;
    }, 180);
  }

  private onClearRangeStartChange(value: number): void {
    const safeValue = Math.max(0, Math.min(value, this.clearRangeEndPercent));
    this.clearRangeStartPercent = safeValue;
    this.updateClearRangeTimeByPercent();
  }

  private onClearRangeEndChange(value: number): void {
    const safeValue = Math.min(100, Math.max(value, this.clearRangeStartPercent));
    this.clearRangeEndPercent = safeValue;
    this.updateClearRangeTimeByPercent();
  }

  private updateClearRangeTimeByPercent(): void {
    this.clearRangeStartTime = this.percentToTimestamp(this.clearRangeStartPercent);
    this.clearRangeEndTime = this.percentToTimestamp(this.clearRangeEndPercent);
    this.clearRangeSelectedCount = this.getSelectedRangeDeleteCount();
  }

  private percentToTimestamp(percent: number): number {
    const span = this.clearRangeMaxTime - this.clearRangeMinTime;
    if (span <= 0) {
      return this.clearRangeMinTime;
    }
    const safePercent = Math.max(0, Math.min(100, percent));
    return Math.round(this.clearRangeMinTime + span * (safePercent / 100));
  }

  private isRecordInSelectedRange(timestamp: number): boolean {
    return timestamp >= this.clearRangeStartTime && timestamp <= this.clearRangeEndTime;
  }

  private getSelectedRangeDeleteCount(): number {
    let count = 0;
    for (let i = 0; i < this.allRecords.length; i++) {
      if (this.isRecordInSelectedRange(this.allRecords[i].timestamp)) {
        count++;
      }
    }
    return count;
  }

  private isFullRangeSelected(): boolean {
    return this.clearRangeStartPercent <= 0 && this.clearRangeEndPercent >= 100;
  }

  private confirmClearByRange(): void {
    if (this.isClearing) {
      return;
    }
    const targetRecords = this.allRecords.filter((r: ErrorRecord) => this.isRecordInSelectedRange(r.timestamp));
    if (targetRecords.length === 0) {
      this.closeClearRangePanel();
      return;
    }
    const deleteAll = targetRecords.length === this.allRecords.length || this.isFullRangeSelected();
    logger.info(
      TAG,
      `开始删除错误日志 mode=${deleteAll ? 'full' : 'range'}, records=${targetRecords.length}, range=${this.formatFullTime(this.clearRangeStartTime)}~${this.formatFullTime(this.clearRangeEndTime)}`
    );
    this.isClearing = true;
    this.closeClearRangePanel();

    animateTo({ duration: 180, curve: Curve.EaseInOut }, () => {
      this.recordsListOpacity = 0;
      this.recordsListScale = 0.98;
    });

    setTimeout(() => {
      try {
        const deleteStats = this.applyRangeDelete(targetRecords, deleteAll);
        this.logDeleteSummary(deleteStats);
        this.selectedIds = [];
        this.isSelectMode = false;
        this.expandedId = '';
        this.loadData();
      } catch (error) {
        logger.error(TAG, `按时间区间删除错误记录失败: ${String(error)}`);
      }

      this.recordsListOpacity = 0;
      this.recordsListScale = 1.02;
      animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
        this.recordsListOpacity = 1;
        this.recordsListScale = 1;
      });
      this.isClearing = false;
    }, 190);
  }

  private applyRangeDelete(targetRecords: ErrorRecord[], deleteAll: boolean): DeleteExecutionStats {
    const stats = new DeleteExecutionStats();
    stats.mode = deleteAll ? 'full' : 'range';
    stats.targetedRecords = targetRecords.length;
    const fileNameSet: Set<string> = new Set<string>();
    for (let i = 0; i < targetRecords.length; i++) {
      const fileName = targetRecords[i].logFileName;
      if (fileName && fileName.length > 0) {
        fileNameSet.add(fileName);
      }
    }
    stats.targetedLogFileNames = fileNameSet.size;

    if (deleteAll) {
      this.errorRecordManager.clearAll();
    } else {
      for (let i = 0; i < targetRecords.length; i++) {
        this.errorRecordManager.deleteRecord(targetRecords[i].id);
      }
    }

    this.deleteLogFilesByName(fileNameSet, stats);
    if (deleteAll) {
      this.deleteResidualLogFiles(stats);
    }
    return stats;
  }

  private deleteLogFilesByName(fileNameSet: Set<string>, stats: DeleteExecutionStats): void {
    if (fileNameSet.size === 0) {
      return;
    }
    const dirs = this.resolveKnownLogDirs();

    fileNameSet.forEach((rawFileName: string) => {
      const fileName = this.normalizeLogFileName(rawFileName);
      if (!fileName) {
        return;
      }
      if (dirs.errorLogsDir.length > 0) {
        this.safeDeleteFile(`${dirs.errorLogsDir}/${fileName}`, stats, 'error_logs');
      }
      if (dirs.crashLogsDir.length > 0) {
        this.safeDeleteFile(`${dirs.crashLogsDir}/${fileName}`, stats, 'crash_logs');
      }
      if (dirs.downloadLogsDir.length > 0) {
        this.safeDeleteFile(`${dirs.downloadLogsDir}/${fileName}`, stats, 'download_logs');
      }
    });
  }

  private deleteResidualLogFiles(stats: DeleteExecutionStats): void {
    const dirs = this.resolveKnownLogDirs();

    if (dirs.errorLogsDir.length > 0) {
      this.deleteFilesByMatcher(
        dirs.errorLogsDir,
        (name: string) => name.startsWith('error_') && name.endsWith('.txt'),
        stats,
        'residual_error_logs'
      );
    }
    if (dirs.crashLogsDir.length > 0) {
      this.deleteFilesByMatcher(
        dirs.crashLogsDir,
        (name: string) => name.startsWith('crash_') && name.endsWith('.txt'),
        stats,
        'residual_crash_logs'
      );
      this.safeDeleteFile(`${dirs.crashLogsDir}/last_crash_summary.json`, stats, 'residual_crash_logs');
    }

    if (dirs.downloadLogsDir.length > 0) {
      this.deleteFilesByMatcher(
        dirs.downloadLogsDir,
        (name: string) => (name.startsWith('error_') || name.startsWith('crash_')) && name.endsWith('.txt'),
        stats,
        'residual_download_logs'
      );
    }
  }

  private resolveKnownLogDirs(): KnownLogDirs {
    const filesDir = this.getSandboxFilesDir();
    let errorLogsDir = getErrorMonitorService().getErrorLogsDir();
    let crashLogsDir = getCrashRecorderService().getCrashLogsDir();
    if (!errorLogsDir && filesDir.length > 0) {
      errorLogsDir = `${filesDir}/error_logs`;
    }
    if (!crashLogsDir && filesDir.length > 0) {
      crashLogsDir = `${filesDir}/crash_logs`;
    }
    const downloadDirManager = DownloadDirManager.getInstance();
    const downloadLogsDir = downloadDirManager.isReady() ? `${downloadDirManager.getPath()}/logs` : '';
    const dirs: KnownLogDirs = new KnownLogDirs();
    dirs.errorLogsDir = errorLogsDir;
    dirs.crashLogsDir = crashLogsDir;
    dirs.downloadLogsDir = downloadLogsDir;
    return dirs;
  }

  private getSandboxFilesDir(): string {
    try {
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (context && context.filesDir) {
        return context.filesDir;
      }
    } catch {
      // ignore
    }
    return '';
  }

  private normalizeLogFileName(fileName: string): string {
    if (!fileName) {
      return '';
    }
    const normalized = fileName.replace(/\\/g, '/');
    const parts = normalized.split('/');
    return parts.length > 0 ? parts[parts.length - 1] : '';
  }

  private deleteFilesByMatcher(
    dirPath: string,
    matcher: (name: string) => boolean,
    stats: DeleteExecutionStats,
    scope: string
  ): void {
    if (!dirPath) {
      return;
    }
    const files = this.safeListFiles(dirPath);
    for (let i = 0; i < files.length; i++) {
      const fileName = files[i];
      if (matcher(fileName)) {
        this.safeDeleteFile(`${dirPath}/${fileName}`, stats, scope);
      }
    }
  }

  private safeListFiles(dirPath: string): string[] {
    if (!dirPath) {
      return [];
    }
    try {
      return fs.listFileSync(dirPath);
    } catch {
      return [];
    }
  }

  private safeDeleteFile(filePath: string, stats: DeleteExecutionStats, scope: string): void {
    if (!filePath) {
      return;
    }
    this.increaseDeleteScopeCount(stats, scope);
    stats.attemptedDeletes++;
    try {
      fs.unlinkSync(filePath);
      stats.successfulDeletes++;
    } catch (error) {
      stats.failedDeletes++;
      if (stats.failedSamples.length < 8) {
        stats.failedSamples.push(`[${scope}] ${filePath} :: ${String(error)}`);
      }
    }
  }

  private increaseDeleteScopeCount(stats: DeleteExecutionStats, scope: string): void {
    if (scope === 'error_logs') {
      stats.errorLogsAttempts++;
      return;
    }
    if (scope === 'crash_logs') {
      stats.crashLogsAttempts++;
      return;
    }
    if (scope === 'download_logs') {
      stats.downloadLogsAttempts++;
      return;
    }
    stats.residualAttempts++;
  }

  private logDeleteSummary(stats: DeleteExecutionStats): void {
    logger.info(
      TAG,
      `删除完成 mode=${stats.mode}, records=${stats.targetedRecords}, mappedFiles=${stats.targetedLogFileNames}, attempt=${stats.attemptedDeletes}, success=${stats.successfulDeletes}, failed=${stats.failedDeletes}, scope(error=${stats.errorLogsAttempts},crash=${stats.crashLogsAttempts},download=${stats.downloadLogsAttempts},residual=${stats.residualAttempts})`
    );
    if (stats.failedDeletes > 0) {
      logger.warn(
        TAG,
        `删除存在失败 failed=${stats.failedDeletes}, samples=${stats.failedSamples.length}: ${stats.failedSamples.join(' | ')}`
      );
    }
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
      logger.info(TAG, `错误报告已导出 ${targetUri}`);
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

  private formatFullTime(ts: number): string {
    if (ts === 0) return '-';
    const d = new Date(ts);
    const Y = d.getFullYear();
    const M = (d.getMonth() + 1).toString().padStart(2, '0');
    const D = d.getDate().toString().padStart(2, '0');
    const h = d.getHours().toString().padStart(2, '0');
    const m = d.getMinutes().toString().padStart(2, '0');
    const s = d.getSeconds().toString().padStart(2, '0');
    return `${Y}-${M}-${D} ${h}:${m}:${s}`;
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

  private getRecordCategory(record: ErrorRecord): CategoryFilterType {
    if (record.category) {
      return record.category as CategoryFilterType;
    }
    if (record.source === ErrorSource.NETWORK_ERROR) {
      return 'network';
    }
    if (record.source === ErrorSource.CRASH) {
      return 'system';
    }
    return 'unknown';
  }

  private getCategoryLabel(category: CategoryFilterType): string {
    switch (category) {
      case 'network': return '网络';
      case 'download': return '下载';
      case 'storage': return '存储';
      case 'data': return '数据';
      case 'parser': return '解析';
      case 'source': return '书源图源';
      case 'webview': return 'WebView';
      case 'auth': return '认证';
      case 'sync': return '同步';
      case 'ui': return '界面';
      case 'system': return '系统';
      case 'unknown': return '未分类';
      default: return '全部';
    }
  }

  private getCategoryColor(category: CategoryFilterType): ResourceColor {
    switch (category) {
      case 'network':
        return ThemeAwareHelper.getTestManagementThemedColor('button_purple', this.themeState.currentTheme);
      case 'download':
        return ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme);
      case 'storage':
        return ThemeAwareHelper.getTestManagementThemedColor('button_warning', this.themeState.currentTheme);
      case 'data':
        return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme);
      case 'parser':
        return ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme);
      case 'source':
        return ThemeAwareHelper.getTestManagementThemedColor('brand', this.themeState.currentTheme);
      case 'webview':
        return ThemeAwareHelper.getTestManagementThemedColor('button_info', this.themeState.currentTheme);
      case 'auth':
        return ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme);
      case 'sync':
        return ThemeAwareHelper.getTestManagementThemedColor('brand_secondary', this.themeState.currentTheme);
      case 'ui':
        return ThemeAwareHelper.getTestManagementThemedColor('accent_secondary', this.themeState.currentTheme);
      case 'system':
        return ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme);
      default:
        return ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme);
    }
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

        if (this.summary.categoryCounts.length > 0) {
          Column({ space: 4 }) {
            Text('分类分布')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(this.themeColor('text_secondary'))
            Row({ space: 8 }) {
              ForEach(this.summary.categoryCounts.slice(0, 4), (cc: CategoryCount) => {
                Text(`${this.getCategoryLabel(cc.category as CategoryFilterType)} ${cc.count}`)
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.themeColor('text_muted'))
                  .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                  .backgroundColor(this.themeColor('comp_background_tertiary'))
                  .borderRadius(6)
              }, (cc: CategoryCount) => cc.category)
            }
            .width('100%')
          }
          .width('100%')
        }

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
      TextInput({ placeholder: '搜索错误信息...', text: this.searchText })
        .width('100%')
        .height(38)
        .backgroundColor(this.themeColor('panel_background'))
        .borderRadius(8)
        .onChange((v: string) => { this.searchText = v; this.applyFilter(); })

      Row({ space: 8 }) {
        this.buildFilterBtn('全部', 'all')
        this.buildFilterBtn('运行时', 'runtime')
        this.buildFilterBtn('网络', 'network')
        this.buildFilterBtn('闪退', 'crash')

        Blank()

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

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        this.buildCategoryFilterBtn('全部', 'all')
        this.buildCategoryFilterBtn('网络', 'network')
        this.buildCategoryFilterBtn('下载', 'download')
        this.buildCategoryFilterBtn('存储', 'storage')
        this.buildCategoryFilterBtn('数据', 'data')
        this.buildCategoryFilterBtn('解析', 'parser')
        this.buildCategoryFilterBtn('书源图源', 'source')
        this.buildCategoryFilterBtn('WebView', 'webview')
        this.buildCategoryFilterBtn('认证', 'auth')
        this.buildCategoryFilterBtn('同步', 'sync')
        this.buildCategoryFilterBtn('界面', 'ui')
        this.buildCategoryFilterBtn('系统', 'system')
        this.buildCategoryFilterBtn('未分类', 'unknown')
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
  buildCategoryFilterBtn(label: string, type: CategoryFilterType) {
    Button({ stateEffect: true }) {
      Text(label)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.themeColor('button_text_secondary'))
    }
    .height(28)
    .padding({ left: 10, right: 10 })
    .backgroundColor(
      this.categoryFilterType === type
        ? this.themeColor('brand_blue')
        : this.themeColor('button_inactive')
    )
    .borderRadius(6)
    .margin({ right: 8, bottom: 8 })
    .onClick(() => { this.categoryFilterType = type; this.applyFilter(); })
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
        .enabled(this.allRecords.length > 0 && !this.isClearing)
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

        Text(this.getCategoryLabel(this.getRecordCategory(record)))
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor(Color.White)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor(this.getCategoryColor(this.getRecordCategory(record)))
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

  @Builder
  buildClearRangePanel() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .opacity(this.clearPanelOpacity)
        .onClick(() => {
          if (!this.isClearing) {
            this.closeClearRangePanel();
          }
        })

      Column({ space: 12 }) {
        Text('删除错误日志')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(this.themeColor('text_primary'))
          .width('100%')

        Text('请选择起止时间区间，仅删除区间内的错误记录与对应的日志文件。')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.themeColor('text_muted'))
          .width('100%')

        Row({ space: 8 }) {
          Text(`起始: ${this.formatFullTime(this.clearRangeStartTime)}`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(this.themeColor('text_secondary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`结束: ${this.formatFullTime(this.clearRangeEndTime)}`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(this.themeColor('text_secondary'))
            .layoutWeight(1)
            .maxLines(1)
            .textAlign(TextAlign.End)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')

        Text(`将删除 ${this.clearRangeSelectedCount} 条错误记录`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(this.themeColor('button_danger'))
          .width('100%')

        Column({ space: 6 }) {
          Text('起始时间进度')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(this.themeColor('text_muted'))
            .width('100%')
          Slider({ value: this.clearRangeStartPercent, min: 0, max: 100, step: 1, style: SliderStyle.OutSet })
            .blockColor(this.themeColor('accent_blue'))
            .trackColor(this.themeColor('panel_border'))
            .selectedColor(this.themeColor('accent_blue'))
            .showTips(false)
            .onChange((value: number, _mode: SliderChangeMode) => {
              this.onClearRangeStartChange(value);
            })
            .width('100%')
        }
        .width('100%')

        Column({ space: 6 }) {
          Text('结束时间进度')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(this.themeColor('text_muted'))
            .width('100%')
          Slider({ value: this.clearRangeEndPercent, min: 0, max: 100, step: 1, style: SliderStyle.OutSet })
            .blockColor(this.themeColor('button_danger'))
            .trackColor(this.themeColor('panel_border'))
            .selectedColor(this.themeColor('button_danger'))
            .showTips(false)
            .onChange((value: number, _mode: SliderChangeMode) => {
              this.onClearRangeEndChange(value);
            })
            .width('100%')
        }
        .width('100%')

        Row() {
          Text(this.formatShortTime(this.clearRangeMinTime))
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(this.themeColor('text_tertiary'))
            .layoutWeight(1)
          Text(this.formatShortTime(this.clearRangeMaxTime))
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(this.themeColor('text_tertiary'))
        }
        .width('100%')

        Row({ space: 10 }) {
          Button({ stateEffect: true }) {
            Text('取消')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(this.themeColor('button_text_secondary'))
          }
          .layoutWeight(1)
          .height(34)
          .backgroundColor(this.themeColor('button_inactive'))
          .borderRadius(8)
          .enabled(!this.isClearing)
          .onClick(() => { this.closeClearRangePanel(); })

          Button({ stateEffect: true }) {
            Text(this.isClearing ? '删除中...' : '确认删除')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(this.themeColor('button_text_secondary'))
          }
          .layoutWeight(1)
          .height(34)
          .backgroundColor(this.themeColor('button_danger'))
          .borderRadius(8)
          .enabled(!this.isClearing && this.clearRangeSelectedCount > 0)
          .onClick(() => { this.confirmClearByRange(); })
        }
        .width('100%')
      }
      .width('90%')
      .constraintSize({ maxWidth: 560 })
      .padding(16)
      .backgroundColor(this.themeColor('panel_background'))
      .borderRadius(14)
      .border({ width: 1, color: this.themeColor('panel_border') })
      .shadow({ radius: 16, color: this.themeColor('shadow_black'), offsetY: 6 })
      .opacity(this.clearPanelOpacity)
      .scale({ x: this.clearPanelScale, y: this.clearPanelScale })
    }
    .width('100%')
    .height('100%')
    .zIndex(3000)
    .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
      .combine(TransitionEffect.scale({ x: 0.95, y: 0.95 }).animation({ duration: 200, curve: Curve.EaseOut })))
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

            // 错误列表（清空时淡出/淡入）
            Column() {
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
            }
            .width('100%')
            .opacity(this.recordsListOpacity)
            .scale({ x: this.recordsListScale, y: this.recordsListScale })
            .animation({ duration: 220, curve: Curve.EaseOut })

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

        if (this.showClearRangePanel) {
          this.buildClearRangePanel()
        }
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
