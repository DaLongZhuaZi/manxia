import { HdsNavDestination } from '@kit.UIDesignKit';
import { common } from '@kit.AbilityKit';
import { logger } from '../Utils/Logger';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { ThemeAwareHelper, ThemeAwareState } from '../Framework/Components/ThemeAware';
import {
  StorageBucketId,
  StorageBucketSummary,
  StorageClearResult,
  StorageDashboardService,
  StorageDashboardSnapshot,
  StorageSectionId,
  StorageSectionSummary
} from '../Framework/Storage/StorageDashboardService';
import { getHelpPanelManagerV2 } from '../Framework/Components/HelpPanelV2';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsImmersiveTitleActionItem, SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';
import { GlobalBackgroundLayerMode } from '../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsPanelSurfaceHelper } from './settings/SettingsPanelSurfaceHelper';

const TAG = 'StorageManagementPage';
const STORAGE_AUTO_REFRESH_INTERVAL_MS: number = 3500;

@Component
export struct StorageManagementPage {
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  @State private snapshot: StorageDashboardSnapshot | null = null;
  @State private selectedBucketIds: StorageBucketId[] = [];
  @State private isLoading: boolean = true;
  @State private isRefreshing: boolean = false;
  @State private isClearing: boolean = false;
  @State private hasLoaded: boolean = false;
  @State private errorMessage: string = '';
  @State private snapshotRenderVersion: number = 0;
  @State private isCleanableSectionExpanded: boolean = true;
  @State private isRemoteCacheSectionExpanded: boolean = true;
  @State private isMemorySectionExpanded: boolean = true;
  @State private isProtectedSectionExpanded: boolean = true;

  private readonly storageService: StorageDashboardService = StorageDashboardService.getInstance();
  private readonly componentId: string = TAG;
  private silentRefreshSequenceToken: number = 0;
  private pendingSilentRefreshTimers: number[] = [];
  private pendingOptimisticBucketIds: StorageBucketId[] = [];
  private refreshTimer: number = -1;
  private isSnapshotRefreshRunning: boolean = false;
  private snapshotRefreshGeneration: number = 0;

  aboutToAppear(): void {
    logger.lifecycle(TAG, 'aboutToAppear');
    ThemeAwareHelper.initializeThemeAware(
      this.componentId,
      this.themeState,
      undefined,
      (newState: ThemeAwareState) => {
        this.themeState = newState;
      }
    );
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );
    void this.loadSnapshot(true, false);
    this.startRefreshTimer();
  }

  aboutToDisappear(): void {
    logger.lifecycle(TAG, 'aboutToDisappear');
    this.stopRefreshTimer();
    this.invalidateSilentRefreshSequence();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }

  private getAbilityContext(): common.UIAbilityContext | null {
    try {
      return this.getUIContext()?.getHostContext() as common.UIAbilityContext;
    } catch (error) {
      logger.error(TAG, `读取Ability上下文失败: ${String(error)}`);
      return null;
    }
  }

  private getTitleBarActions(): SettingsImmersiveTitleActionItem[] {
    return [{
      id: 'help',
      label: '帮助',
      symbol: $r('sys.symbol.questionmark_circle'),
      onClick: () => {
        this.showStorageHelp();
      }
    }];
  }

  private commitSnapshot(snapshot: StorageDashboardSnapshot): void {
    this.snapshot = snapshot;
    this.snapshotRenderVersion += 1;
    logger.debug(
      TAG,
      `提交存储快照: version=${this.snapshotRenderVersion}, scanned=${snapshot.overview.scannedTotalSizeBytes}, cleanable=${snapshot.overview.cleanableTotalSizeBytes}, selected=${this.selectedBucketIds.length}, updatedAt=${snapshot.overview.updatedAt}`
    );
  }

  private async loadSnapshot(forceRefresh: boolean, showRefreshToast: boolean): Promise<void> {
    if (this.isSnapshotRefreshRunning) {
      if (showRefreshToast) {
        this.showToast('正在刷新存储信息');
      }
      return;
    }

    const abilityContext = this.getAbilityContext();
    if (!abilityContext) {
      this.errorMessage = '无法读取应用上下文，暂时不能扫描存储信息';
      this.isLoading = false;
      this.isRefreshing = false;
      this.hasLoaded = true;
      return;
    }

    this.isSnapshotRefreshRunning = true;
    const refreshGeneration = this.snapshotRefreshGeneration;
    if (!this.hasLoaded) {
      this.isLoading = true;
    } else {
      this.isRefreshing = true;
    }

    this.errorMessage = '';
    try {
      const snapshot = await this.storageService.inspect(abilityContext, forceRefresh);
      if (refreshGeneration !== this.snapshotRefreshGeneration) {
        logger.debug(TAG, `存储快照刷新结果已过期，跳过提交: generation=${refreshGeneration}`);
        return;
      }
      if (this.shouldSkipSilentRefreshSnapshot(snapshot)) {
        logger.debug(TAG, `存储快照刷新结果已跳过，等待清理后复扫稳定: generation=${refreshGeneration}`);
        return;
      }
      this.commitSnapshot(snapshot);
      this.trimSelection();
      if (showRefreshToast) {
        this.showToast('存储信息已刷新');
      }
    } catch (error) {
      const message = `读取存储信息失败: ${String(error)}`;
      logger.error(TAG, message);
      this.errorMessage = message;
      if (showRefreshToast) {
        this.showToast('刷新失败');
      }
    } finally {
      this.isLoading = false;
      this.isRefreshing = false;
      this.hasLoaded = true;
      this.isSnapshotRefreshRunning = false;
    }
  }

  private async refreshSnapshot(): Promise<void> {
    if (this.isSnapshotRefreshRunning) {
      this.showToast('正在刷新存储信息');
      return;
    }
    this.invalidateSilentRefreshSequence();
    await this.loadSnapshot(true, true);
  }

  private startRefreshTimer(): void {
    this.stopRefreshTimer();
    this.refreshTimer = setInterval(() => {
      this.runPeriodicRefresh();
    }, STORAGE_AUTO_REFRESH_INTERVAL_MS) as number;
  }

  private stopRefreshTimer(): void {
    if (this.refreshTimer >= 0) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = -1;
    }
  }

  private runPeriodicRefresh(): void {
    if (!this.hasLoaded || this.isLoading || this.isClearing || this.isSnapshotRefreshRunning) {
      return;
    }
    void this.loadSnapshot(true, false);
  }

  private invalidateSilentRefreshSequence(): void {
    this.silentRefreshSequenceToken += 1;
    this.snapshotRefreshGeneration += 1;
    for (let index = 0; index < this.pendingSilentRefreshTimers.length; index++) {
      clearTimeout(this.pendingSilentRefreshTimers[index]);
    }
    this.pendingSilentRefreshTimers = [];
    this.pendingOptimisticBucketIds = [];
  }

  private scheduleSilentRefreshSequence(clearedBucketIds: StorageBucketId[]): void {
    const abilityContext = this.getAbilityContext();
    if (!abilityContext) {
      return;
    }

    this.invalidateSilentRefreshSequence();
    for (let index = 0; index < clearedBucketIds.length; index++) {
      this.pendingOptimisticBucketIds.push(clearedBucketIds[index]);
    }
    const refreshToken = this.silentRefreshSequenceToken;
    this.enqueueSilentRefresh(abilityContext, refreshToken, 260);
    this.enqueueSilentRefresh(abilityContext, refreshToken, 820);
    this.enqueueSilentRefresh(abilityContext, refreshToken, 1680);
    this.enqueueSilentRefresh(abilityContext, refreshToken, 3200);
    this.enqueueSilentRefresh(abilityContext, refreshToken, 5200);
  }

  private enqueueSilentRefresh(
    abilityContext: common.UIAbilityContext,
    refreshToken: number,
    delayMs: number
  ): void {
    const timerId: number = setTimeout(() => {
      this.removeSilentRefreshTimer(timerId);
      if (refreshToken !== this.silentRefreshSequenceToken) {
        return;
      }
      void this.runSilentRefresh(abilityContext, refreshToken);
    }, delayMs) as number;
    this.pendingSilentRefreshTimers.push(timerId);
  }

  private removeSilentRefreshTimer(timerId: number): void {
    const nextTimers: number[] = [];
    for (let index = 0; index < this.pendingSilentRefreshTimers.length; index++) {
      const currentTimerId = this.pendingSilentRefreshTimers[index];
      if (currentTimerId !== timerId) {
        nextTimers.push(currentTimerId);
      }
    }
    this.pendingSilentRefreshTimers = nextTimers;
  }

  private async runSilentRefresh(
    abilityContext: common.UIAbilityContext,
    refreshToken: number
  ): Promise<void> {
    try {
      const snapshot = await this.storageService.inspect(abilityContext, true);
      if (refreshToken !== this.silentRefreshSequenceToken) {
        return;
      }
      if (this.shouldSkipSilentRefreshSnapshot(snapshot)) {
        logger.debug(TAG, `静默刷新结果已跳过: token=${refreshToken}, version=${this.snapshotRenderVersion}`);
        return;
      }
      this.commitSnapshot(snapshot);
      this.errorMessage = '';
      this.hasLoaded = true;
      this.trimSelection();
    } catch (error) {
      if (refreshToken !== this.silentRefreshSequenceToken) {
        return;
      }
      logger.debug(TAG, `静默刷新存储信息失败: ${String(error)}`);
    } finally {
      this.completeSilentRefreshAttempt(refreshToken);
    }
  }

  private completeSilentRefreshAttempt(refreshToken: number): void {
    if (refreshToken !== this.silentRefreshSequenceToken) {
      return;
    }
    if (this.pendingSilentRefreshTimers.length > 0) {
      return;
    }
    this.pendingOptimisticBucketIds = [];
  }

  private shouldSkipSilentRefreshSnapshot(nextSnapshot: StorageDashboardSnapshot): boolean {
    const currentSnapshot = this.snapshot;
    if (!currentSnapshot || this.pendingOptimisticBucketIds.length <= 0) {
      return false;
    }

    for (let index = 0; index < this.pendingOptimisticBucketIds.length; index++) {
      const bucketId = this.pendingOptimisticBucketIds[index];
      const currentBucket = this.findBucketInSnapshot(currentSnapshot, bucketId);
      const nextBucket = this.findBucketInSnapshot(nextSnapshot, bucketId);
      if (!currentBucket || !nextBucket) {
        continue;
      }
      if (nextBucket.sizeBytes > currentBucket.sizeBytes || nextBucket.itemCount > currentBucket.itemCount) {
        logger.debug(
          TAG,
          `检测到回退快照，跳过覆盖: bucket=${bucketId}, current=${currentBucket.sizeBytes}/${currentBucket.itemCount}, next=${nextBucket.sizeBytes}/${nextBucket.itemCount}`
        );
        return true;
      }
    }
    return false;
  }

  private trimSelection(): void {
    const snapshot = this.snapshot;
    if (!snapshot) {
      this.selectedBucketIds = [];
      return;
    }

    const nextSelected: StorageBucketId[] = [];
    for (let index = 0; index < this.selectedBucketIds.length; index++) {
      const bucketId = this.selectedBucketIds[index];
      const bucket = this.findBucketById(bucketId);
      if (bucket && this.isBucketActionable(bucket)) {
        nextSelected.push(bucketId);
      }
    }
    this.selectedBucketIds = nextSelected;
  }

  private getSuccessfulBucketIds(result: StorageClearResult): StorageBucketId[] {
    const bucketIds: StorageBucketId[] = [];
    for (let index = 0; index < result.results.length; index++) {
      const item = result.results[index];
      if (item.success) {
        bucketIds.push(item.id);
      }
    }
    return bucketIds;
  }

  private applyOptimisticSnapshot(clearedBucketIds: StorageBucketId[]): void {
    const snapshot = this.snapshot;
    if (!snapshot || clearedBucketIds.length <= 0) {
      return;
    }

    this.commitSnapshot(this.storageService.createOptimisticSnapshot(snapshot, clearedBucketIds));
    this.errorMessage = '';
    this.hasLoaded = true;
    this.trimSelection();
  }

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  private findBucketById(bucketId: StorageBucketId): StorageBucketSummary | null {
    const snapshot = this.snapshot;
    if (!snapshot) {
      return null;
    }

    return this.findBucketInSnapshot(snapshot, bucketId);
  }

  private findBucketInSnapshot(snapshot: StorageDashboardSnapshot, bucketId: StorageBucketId): StorageBucketSummary | null {
    for (let index = 0; index < snapshot.buckets.length; index++) {
      const bucket = snapshot.buckets[index];
      if (bucket.id === bucketId) {
        return bucket;
      }
    }
    return null;
  }

  private isBucketSelected(bucketId: StorageBucketId): boolean {
    for (let index = 0; index < this.selectedBucketIds.length; index++) {
      if (this.selectedBucketIds[index] === bucketId) {
        return true;
      }
    }
    return false;
  }

  private isBucketActionable(bucket: StorageBucketSummary): boolean {
    if (!bucket.isClearable) {
      return false;
    }
    return bucket.sizeBytes > 0 || bucket.itemCount > 0;
  }

  private toggleBucketSelection(bucket: StorageBucketSummary): void {
    if (!bucket.isClearable) {
      this.showToast('该项属于受保护数据，只做展示');
      return;
    }
    if (!this.isBucketActionable(bucket)) {
      this.showToast('当前没有可清理内容');
      return;
    }

    const nextSelected: StorageBucketId[] = [];
    let removed = false;
    for (let index = 0; index < this.selectedBucketIds.length; index++) {
      const selectedId = this.selectedBucketIds[index];
      if (selectedId === bucket.id) {
        removed = true;
        continue;
      }
      nextSelected.push(selectedId);
    }
    if (!removed) {
      nextSelected.push(bucket.id);
    }
    this.selectedBucketIds = nextSelected;
  }

  private getSelectedBuckets(): StorageBucketSummary[] {
    const selectedBuckets: StorageBucketSummary[] = [];
    for (let index = 0; index < this.selectedBucketIds.length; index++) {
      const bucket = this.findBucketById(this.selectedBucketIds[index]);
      if (bucket) {
        selectedBuckets.push(bucket);
      }
    }
    return selectedBuckets;
  }

  private getSelectedSizeBytes(): number {
    let totalSizeBytes = 0;
    const selectedBuckets = this.getSelectedBuckets();
    for (let index = 0; index < selectedBuckets.length; index++) {
      totalSizeBytes += selectedBuckets[index].sizeBytes;
    }
    return totalSizeBytes;
  }

  private getClearableBuckets(): StorageBucketSummary[] {
    const buckets: StorageBucketSummary[] = [];
    const snapshot = this.snapshot;
    if (!snapshot) {
      return buckets;
    }

    for (let index = 0; index < snapshot.buckets.length; index++) {
      const bucket = snapshot.buckets[index];
      if (this.isBucketActionable(bucket)) {
        buckets.push(bucket);
      }
    }
    return buckets;
  }

  private areAllClearableBucketsSelected(): boolean {
    const clearableBuckets = this.getClearableBuckets();
    if (clearableBuckets.length <= 0) {
      return false;
    }

    for (let index = 0; index < clearableBuckets.length; index++) {
      if (!this.isBucketSelected(clearableBuckets[index].id)) {
        return false;
      }
    }
    return true;
  }

  private toggleSelectAllClearable(): void {
    if (this.areAllClearableBucketsSelected()) {
      this.selectedBucketIds = [];
      return;
    }

    const nextSelected: StorageBucketId[] = [];
    const clearableBuckets = this.getClearableBuckets();
    for (let index = 0; index < clearableBuckets.length; index++) {
      nextSelected.push(clearableBuckets[index].id);
    }
    this.selectedBucketIds = nextSelected;
  }

  private getSectionBuckets(sectionId: StorageSectionId): StorageBucketSummary[] {
    const buckets: StorageBucketSummary[] = [];
    const snapshot = this.snapshot;
    if (!snapshot) {
      return buckets;
    }

    for (let index = 0; index < snapshot.buckets.length; index++) {
      const bucket = snapshot.buckets[index];
      if (bucket.section === sectionId) {
        buckets.push(bucket);
      }
    }
    return buckets;
  }

  private isSectionExpanded(sectionId: StorageSectionId): boolean {
    switch (sectionId) {
      case StorageSectionId.CLEANABLE:
        return this.isCleanableSectionExpanded;
      case StorageSectionId.REMOTE_CACHE:
        return this.isRemoteCacheSectionExpanded;
      case StorageSectionId.MEMORY:
        return this.isMemorySectionExpanded;
      case StorageSectionId.PROTECTED:
        return this.isProtectedSectionExpanded;
      default:
        return true;
    }
  }

  private setSectionExpanded(sectionId: StorageSectionId, expanded: boolean): void {
    switch (sectionId) {
      case StorageSectionId.CLEANABLE:
        this.isCleanableSectionExpanded = expanded;
        break;
      case StorageSectionId.REMOTE_CACHE:
        this.isRemoteCacheSectionExpanded = expanded;
        break;
      case StorageSectionId.MEMORY:
        this.isMemorySectionExpanded = expanded;
        break;
      case StorageSectionId.PROTECTED:
        this.isProtectedSectionExpanded = expanded;
        break;
      default:
        break;
    }
  }

  private toggleSectionExpanded(sectionId: StorageSectionId): void {
    const nextExpanded = !this.isSectionExpanded(sectionId);
    const uiContext = this.getUIContext();
    if (uiContext) {
      uiContext.animateTo({
        duration: 220,
        curve: Curve.EaseInOut
      }, () => {
        this.setSectionExpanded(sectionId, nextExpanded);
      });
      return;
    }
    this.setSectionExpanded(sectionId, nextExpanded);
  }

  private hasSectionSelectableBuckets(sectionId: StorageSectionId): boolean {
    const buckets = this.getSectionBuckets(sectionId);
    for (let index = 0; index < buckets.length; index++) {
      if (this.isBucketActionable(buckets[index])) {
        return true;
      }
    }
    return false;
  }

  private areAllSectionBucketsSelected(sectionId: StorageSectionId): boolean {
    const buckets = this.getSectionBuckets(sectionId);
    let selectableCount = 0;

    for (let index = 0; index < buckets.length; index++) {
      const bucket = buckets[index];
      if (!this.isBucketActionable(bucket)) {
        continue;
      }
      selectableCount += 1;
      if (!this.isBucketSelected(bucket.id)) {
        return false;
      }
    }

    return selectableCount > 0;
  }

  private toggleSectionSelection(sectionId: StorageSectionId): void {
    const buckets = this.getSectionBuckets(sectionId);
    if (!this.hasSectionSelectableBuckets(sectionId)) {
      this.showToast('这一组当前没有可清理内容');
      return;
    }

    const selectAll = !this.areAllSectionBucketsSelected(sectionId);
    const nextSelected: StorageBucketId[] = [];

    for (let index = 0; index < this.selectedBucketIds.length; index++) {
      const selectedId = this.selectedBucketIds[index];
      const bucket = this.findBucketById(selectedId);
      if (bucket && bucket.section === sectionId && this.isBucketActionable(bucket)) {
        continue;
      }
      nextSelected.push(selectedId);
    }

    if (selectAll) {
      for (let index = 0; index < buckets.length; index++) {
        const bucket = buckets[index];
        if (this.isBucketActionable(bucket)) {
          nextSelected.push(bucket.id);
        }
      }
    }

    this.selectedBucketIds = nextSelected;
  }

  private showClearConfirmDialog(bucketIds: StorageBucketId[]): void {
    const clearTargets: StorageBucketSummary[] = [];
    let totalSizeBytes = 0;
    let totalItems = 0;

    for (let index = 0; index < bucketIds.length; index++) {
      const bucket = this.findBucketById(bucketIds[index]);
      if (bucket && this.isBucketActionable(bucket)) {
        clearTargets.push(bucket);
        totalSizeBytes += bucket.sizeBytes;
        totalItems += bucket.itemCount;
      }
    }

    if (clearTargets.length <= 0) {
      this.showToast('没有可清理的项目');
      return;
    }

    const previewLines: string[] = [];
    const previewLimit = 10;
    for (let index = 0; index < clearTargets.length && index < previewLimit; index++) {
      const bucket = clearTargets[index];
      const locationText = this.getBucketLocationText(bucket);
      previewLines.push(
        `• ${bucket.title}\n   ${this.storageService.formatSize(bucket.sizeBytes)} · ${bucket.itemCount} ${bucket.itemLabel}\n   ${locationText}`
      );
    }
    if (clearTargets.length > previewLimit) {
      previewLines.push(`• 以及另外 ${clearTargets.length - previewLimit} 项`);
    }

    this.getUIContext().showAlertDialog({
      title: '确认清理',
      message: `${previewLines.join('\n\n')}\n\n总计 ${this.storageService.formatSize(totalSizeBytes)} · ${totalItems} 项\n此操作会直接删除对应缓存文件，部分离线内容稍后需要重新拉取。`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '开始清理',
        action: () => {
          void this.performClear(bucketIds);
        }
      }
    });
  }

  private async performClear(bucketIds: StorageBucketId[]): Promise<void> {
    const abilityContext = this.getAbilityContext();
    if (!abilityContext) {
      this.showToast('当前无法执行清理');
      return;
    }

    this.invalidateSilentRefreshSequence();
    this.isClearing = true;
    try {
      const result = await this.storageService.clearBuckets(abilityContext, bucketIds);
      const successfulBucketIds = this.getSuccessfulBucketIds(result);
      this.removeSelectedBucketIds(successfulBucketIds);
      this.applyOptimisticSnapshot(successfulBucketIds);
      if (successfulBucketIds.length > 0) {
        this.scheduleSilentRefreshSequence(successfulBucketIds);
      }
      this.showClearResult(result);
    } catch (error) {
      logger.error(TAG, `执行清理失败: ${String(error)}`);
      this.showToast('清理失败');
    } finally {
      this.isClearing = false;
    }
  }

  private removeSelectedBucketIds(bucketIds: StorageBucketId[]): void {
    const nextSelected: StorageBucketId[] = [];
    for (let index = 0; index < this.selectedBucketIds.length; index++) {
      const selectedId = this.selectedBucketIds[index];
      let shouldRemove = false;
      for (let removeIndex = 0; removeIndex < bucketIds.length; removeIndex++) {
        if (bucketIds[removeIndex] === selectedId) {
          shouldRemove = true;
          break;
        }
      }
      if (!shouldRemove) {
        nextSelected.push(selectedId);
      }
    }
    this.selectedBucketIds = nextSelected;
  }

  private showClearResult(result: StorageClearResult): void {
    if (result.success) {
      this.showToast(`已清理 ${this.storageService.formatSize(result.clearedSizeBytes)}`);
      return;
    }

    if (result.clearedSizeBytes > 0) {
      this.showToast(`已清理 ${this.storageService.formatSize(result.clearedSizeBytes)}，部分项目失败`);
      return;
    }

    this.showToast('没有完成任何清理，请稍后重试');
  }

  private getBucketLocationText(bucket: StorageBucketSummary): string {
    if (bucket.path.length > 0) {
      return bucket.path;
    }

    switch (bucket.pathKind) {
      case 'memory':
        return '内存缓存';
      case 'preferences':
        return 'Preferences';
      case 'database':
        return '数据库目录';
      case 'download':
        return 'Download 同步目录';
      case 'system':
        return '系统缓存目录';
      default:
        return '应用沙箱目录';
    }
  }

  private getPathKindLabel(bucket: StorageBucketSummary): string {
    switch (bucket.pathKind) {
      case 'memory':
        return '内存';
      case 'preferences':
        return '偏好';
      case 'database':
        return '数据库';
      case 'download':
        return 'Download';
      case 'system':
        return '系统';
      default:
        return '沙箱';
    }
  }

  private getBucketSymbol(bucket: StorageBucketSummary): Resource {
    switch (bucket.pathKind) {
      case 'memory':
        return $r('sys.symbol.memory_module');
      case 'database':
        return $r('sys.symbol.externaldrive');
      case 'preferences':
        return $r('sys.symbol.gearshape');
      case 'download':
        return $r('sys.symbol.folder');
      case 'system':
        return $r('sys.symbol.externaldrive');
      default:
        return $r('sys.symbol.folder');
    }
  }

  private getSelectionSymbol(bucket: StorageBucketSummary): Resource {
    if (!bucket.isClearable) {
      return $r('sys.symbol.lock');
    }
    return this.isBucketSelected(bucket.id)
      ? $r('sys.symbol.checkmark_circle_fill')
      : $r('sys.symbol.circle');
  }

  private getSelectionColor(bucket: StorageBucketSummary): Resource {
    if (!bucket.isClearable) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme);
    }
    if (!this.isBucketActionable(bucket)) {
      return ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme);
    }
    return this.isBucketSelected(bucket.id)
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
      : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme);
  }

  private getRiskBadgeBackground(bucket: StorageBucketSummary): Resource {
    switch (bucket.risk) {
      case 'caution':
        return ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme);
      case 'protected':
        return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme);
      default:
        return ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme);
    }
  }

  private getRiskBadgeText(bucket: StorageBucketSummary): string {
    switch (bucket.risk) {
      case 'caution':
        return '需重拉';
      case 'protected':
        return '受保护';
      default:
        return '可回收';
    }
  }

  private getBucketRowBackground(bucket: StorageBucketSummary): ResourceColor {
    if (this.isBucketSelected(bucket.id)) {
      return ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme);
    }
    return Color.Transparent;
  }

  private formatUpdatedAt(timestamp: number): string {
    const date = new Date(timestamp);
    const hours = `${date.getHours()}`.padStart(2, '0');
    const minutes = `${date.getMinutes()}`.padStart(2, '0');
    const seconds = `${date.getSeconds()}`.padStart(2, '0');
    return `${hours}:${minutes}:${seconds}`;
  }

  private formatRatioText(part: number, total: number): string {
    if (total <= 0) {
      return '0%';
    }
    const ratio = Math.round((part / total) * 100);
    return `${ratio}%`;
  }

  private getSelectedActionLabel(): string {
    if (this.selectedBucketIds.length <= 0) {
      return '清理已选';
    }
    return `清理已选 ${this.selectedBucketIds.length} 项`;
  }

  private getSectionSelectedSizeBytes(sectionId: StorageSectionId): number {
    let totalSizeBytes = 0;
    const selectedBuckets = this.getSelectedBuckets();
    for (let index = 0; index < selectedBuckets.length; index++) {
      const bucket = selectedBuckets[index];
      if (bucket.section === sectionId) {
        totalSizeBytes += bucket.sizeBytes;
      }
    }
    return totalSizeBytes;
  }

  private getSectionSelectedCount(sectionId: StorageSectionId): number {
    let selectedCount = 0;
    const selectedBuckets = this.getSelectedBuckets();
    for (let index = 0; index < selectedBuckets.length; index++) {
      if (selectedBuckets[index].section === sectionId) {
        selectedCount += 1;
      }
    }
    return selectedCount;
  }

  private isSectionCollapsedSelected(sectionId: StorageSectionId): boolean {
    return !this.isSectionExpanded(sectionId) && this.getSectionSelectedCount(sectionId) > 0;
  }

  private getSectionSummaryDetailText(section: StorageSectionSummary): string {
    if (this.isSectionExpanded(section.id)) {
      return section.subtitle;
    }

    if (section.id === StorageSectionId.PROTECTED) {
      return `展示 ${this.storageService.formatSize(section.totalSizeBytes)} · ${section.bucketCount} 项受保护数据`;
    }

    const selectedCount = this.getSectionSelectedCount(section.id);
    const selectedSizeBytes = this.getSectionSelectedSizeBytes(section.id);
    if (selectedCount > 0) {
      const selectedLabel = section.id === StorageSectionId.MEMORY ? '已选释放' : '已选清理';
      const baseLabel = section.id === StorageSectionId.MEMORY ? '当前占用' : '可回收';
      return `${selectedLabel} ${this.storageService.formatSize(selectedSizeBytes)} · ${baseLabel} ${this.storageService.formatSize(section.clearableSizeBytes)} · ${selectedCount} 项`;
    }

    if (section.id === StorageSectionId.MEMORY) {
      return `当前占用 ${this.storageService.formatSize(section.totalSizeBytes)} · ${section.bucketCount} 项`;
    }

    return `可回收 ${this.storageService.formatSize(section.clearableSizeBytes)} · ${section.bucketCount} 项`;
  }

  private getSectionSummaryMetaText(section: StorageSectionSummary): string {
    if (this.isSectionExpanded(section.id)) {
      return `${section.bucketCount} 项`;
    }

    if (section.id === StorageSectionId.PROTECTED) {
      return `${section.bucketCount} 项`;
    }

    const selectedCount = this.getSectionSelectedCount(section.id);
    if (selectedCount > 0) {
      return `已选 ${selectedCount} 项`;
    }
    return `${section.bucketCount} 项`;
  }

  private getSectionHeaderBackground(sectionId: StorageSectionId): Resource {
    if (this.isSectionExpanded(sectionId)) {
      return ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme);
    }
    if (this.isSectionCollapsedSelected(sectionId)) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme);
    }
    return ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme);
  }

  private getSectionHeaderBorderColor(sectionId: StorageSectionId): Resource {
    if (this.isSectionCollapsedSelected(sectionId)) {
      return ThemeAwareHelper.getTestManagementThemedColor('border_active', this.themeState.currentTheme);
    }
    return ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme);
  }

  private getSectionHeaderDetailColor(sectionId: StorageSectionId): Resource {
    if (this.isSectionCollapsedSelected(sectionId)) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme);
    }
    return ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme);
  }

  private getSectionHeaderMetaColor(sectionId: StorageSectionId): Resource {
    if (this.isSectionCollapsedSelected(sectionId)) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme);
    }
    return ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme);
  }

  private getOverviewProgressTotal(snapshot: StorageDashboardSnapshot): number {
    return snapshot.overview.bundleTotalSizeBytes > 0 ? snapshot.overview.bundleTotalSizeBytes : 1;
  }

  private getSectionLastIndex(sectionId: StorageSectionId): number {
    return this.getSectionBuckets(sectionId).length - 1;
  }

  private showStorageHelp(): void {
    const helpContent = `# 存储管理帮助

## 这个页面会展示什么

- **应用总占用**：系统统计口径下的应用整体空间
- **已扫描目录**：当前已经接入扫描的缓存目录、偏好缓存和受保护目录
- **可直接清理**：清掉后不会影响核心数据的缓存项
- **离线与远端缓存**：清掉后会影响离线阅读、听书或远端浏览，需要后续重新拉取
- **受保护数据**：数据库、导入文件、插件等，仅展示，不在这里直接删除

## 清理逻辑

- 页面会递归扫描目录，而不是只看顶层文件
- 对图源内容缓存、Tab 持久缓存会读取 Preferences 中的实际内容
- 对封面缓存和永久图片缓存，清理时会同步重置对应数据库状态，避免“文件删了但记录还在”

## 使用建议

- 想要快速瘦身，先看“可直接清理”
- 想要腾出更多空间，再看“离线与远端缓存”
- 如果你依赖小说离线、Komga 或 Suwayomi，本页会明确标出风险提示

## 注意

- 本页不会删除书架、阅读记录、插件和数据库
- Download 同步目录未连接时，相关条目会显示但不会误删外部内容`;

    getHelpPanelManagerV2().showInlineHelp('存储管理帮助', helpContent);
  }

  @Builder
  private buildMetricCell(label: string, value: string, note: string) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

      Text(value)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(note)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildOverviewPanel(snapshot: StorageDashboardSnapshot) {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.externaldrive'))
          .fontSize(22)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])

        Column({ space: 4 }) {
          Text('存储总览')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          Text('把系统统计、目录扫描和可清理缓存放到同一张视图里')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      Row({ space: 16 }) {
        this.buildMetricCell('应用总占用', this.storageService.formatSize(snapshot.overview.bundleTotalSizeBytes), '系统统计口径')
        this.buildMetricCell('已扫描目录', this.storageService.formatSize(snapshot.overview.scannedTotalSizeBytes), `${snapshot.overview.bucketCount} 个存储项`)
      }
      .width('100%')

      Divider()
        .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))

      Row({ space: 16 }) {
        this.buildMetricCell('可回收空间', this.storageService.formatSize(snapshot.overview.cleanableTotalSizeBytes), `${this.getClearableBuckets().length} 项当前可清理`)
        this.buildMetricCell('设备剩余', this.storageService.formatSize(snapshot.overview.deviceFreeSizeBytes), '当前设备可用空间')
      }
      .width('100%')

      Column({ space: 8 }) {
        Row() {
          Text('可回收占应用总占用')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          Blank()
          Text(this.formatRatioText(snapshot.overview.cleanableTotalSizeBytes, this.getOverviewProgressTotal(snapshot)))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        }
        .width('100%')

        Progress({
          value: snapshot.overview.cleanableTotalSizeBytes,
          total: this.getOverviewProgressTotal(snapshot),
          type: ProgressType.Linear
        })
          .width('100%')
          .height(8)
          .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(999)
      }
      .width('100%')

      Row() {
        Text(`已更新 ${this.formatUpdatedAt(snapshot.overview.updatedAt)}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        Blank()
        Text(`内存缓存 ${this.storageService.formatSize(snapshot.overview.memorySizeBytes)}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
    }
    .width('100%')
    .padding(18)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .key(`storage_overview_${this.snapshotRenderVersion}`)
  }

  @Builder
  private buildActionPanel() {
    Column({ space: 14 }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(18)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)])

        Column({ space: 4 }) {
          Text(this.selectedBucketIds.length > 0 ? `已选择 ${this.selectedBucketIds.length} 项` : '还没有选择清理项')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          Text(this.selectedBucketIds.length > 0
            ? `预计释放 ${this.storageService.formatSize(this.getSelectedSizeBytes())}`
            : `当前共 ${this.getClearableBuckets().length} 项可直接清理`)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      Row({ space: 12 }) {
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(15)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme)])
            Text(this.isRefreshing ? '刷新中' : '刷新')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
          }
        }
          .layoutWeight(1)
          .height(42)
          .enabled(!this.isLoading && !this.isClearing)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
          .borderRadius(12)
          .onClick(() => {
            void this.refreshSnapshot();
          })

        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Row({ space: 6 }) {
            SymbolGlyph(this.areAllClearableBucketsSelected()
              ? $r('sys.symbol.minus_circle_fill')
              : $r('sys.symbol.checkmark_circle'))
              .fontSize(15)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme)])
            Text(this.areAllClearableBucketsSelected() ? '取消全选' : '全选可清理')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
          }
        }
          .layoutWeight(1)
          .height(42)
          .enabled(!this.isLoading && !this.isClearing && this.getClearableBuckets().length > 0)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
          .borderRadius(12)
          .onClick(() => {
            this.toggleSelectAllClearable();
          })
      }
      .width('100%')

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)])
          Text(this.isClearing ? '清理中...' : this.getSelectedActionLabel())
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        }
      }
        .width('100%')
        .height(46)
        .enabled(this.selectedBucketIds.length > 0 && !this.isClearing)
        .backgroundColor(this.selectedBucketIds.length > 0
          ? ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
        .borderRadius(14)
        .onClick(() => {
          this.showClearConfirmDialog(this.selectedBucketIds);
        })
    }
    .width('100%')
    .padding(18)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .key(
      `storage_action_${this.snapshotRenderVersion}_${this.selectedBucketIds.length}_` +
      `${this.isRefreshing ? 'refreshing' : 'idle'}_${this.isClearing ? 'clearing' : 'ready'}`
    )
  }

  @Builder
  private buildBucketRow(bucket: StorageBucketSummary, isLast: boolean) {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        SymbolGlyph(this.getSelectionSymbol(bucket))
          .fontSize(22)
          .fontColor([this.getSelectionColor(bucket)])
          .margin({ top: 2 })

        Column({ space: 8 }) {
          Row({ space: 8 }) {
            Text(bucket.title)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(this.getRiskBadgeText(bucket))
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor(this.getRiskBadgeBackground(bucket))
              .borderRadius(999)
          }
          .width('100%')

          Text(bucket.subtitle)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Row({ space: 8 }) {
            Text(this.storageService.formatSize(bucket.sizeBytes))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

            Text(`${bucket.itemCount} ${bucket.itemLabel}`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

            Text(this.getPathKindLabel(bucket))
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
              .borderRadius(999)
          }
          .width('100%')

          Row({ space: 6 }) {
            SymbolGlyph(this.getBucketSymbol(bucket))
              .fontSize(12)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
            Text(this.getBucketLocationText(bucket))
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .layoutWeight(1)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)

          if (bucket.note.length > 0) {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.info_circle'))
                .fontSize(12)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)])
              Text(bucket.note)
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .layoutWeight(1)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }

          Progress({
            value: bucket.progressRatio > 0 ? bucket.progressRatio : 0,
            total: 1,
            type: ProgressType.Linear
          })
            .width('100%')
            .height(6)
            .color(bucket.risk === 'caution'
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(999)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 14, bottom: 14 })
    .backgroundColor(this.getBucketRowBackground(bucket))
    .borderRadius(14)
    .key(
      `storage_bucket_${bucket.id}_${this.snapshotRenderVersion}_${bucket.sizeBytes}_${bucket.itemCount}_` +
      `${this.isBucketSelected(bucket.id) ? 'selected' : 'idle'}`
    )
    .onClick(() => {
      this.toggleBucketSelection(bucket);
    })

    if (!isLast) {
      Divider()
        .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
    }
  }

  @Builder
  private buildSectionPanel(section: StorageSectionSummary) {
    Column({ space: 16 }) {
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Row({ space: 12 }) {
          Column({ space: 4 }) {
            Text(section.title)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

            Text(this.getSectionSummaryDetailText(section))
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(this.getSectionHeaderDetailColor(section.id))
              .maxLines(this.isSectionExpanded(section.id) ? 2 : 1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Column({ space: 6 }) {
            Text(this.storageService.formatSize(section.totalSizeBytes))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

            Text(this.getSectionSummaryMetaText(section))
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(this.getSectionHeaderMetaColor(section.id))
          }
          .alignItems(HorizontalAlign.End)

          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(16)
            .fontColor([this.getSectionHeaderMetaColor(section.id)])
            .rotate({ angle: this.isSectionExpanded(section.id) ? 0 : -90 })
            .animation({ duration: 220, curve: Curve.EaseInOut })
        }
        .width('100%')
      }
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .backgroundColor(this.getSectionHeaderBackground(section.id))
        .border({
          width: 1,
          color: this.getSectionHeaderBorderColor(section.id)
        })
        .borderRadius(16)
        .animation({ duration: 220, curve: Curve.EaseInOut })
        .onClick(() => {
          this.toggleSectionExpanded(section.id);
        })

      if (this.isSectionExpanded(section.id)) {
        Column({ space: 14 }) {
          if (this.hasSectionSelectableBuckets(section.id)) {
            Button({ type: ButtonType.Normal, stateEffect: true }) {
              Row({ space: 6 }) {
                SymbolGlyph(this.areAllSectionBucketsSelected(section.id)
                  ? $r('sys.symbol.minus_circle_fill')
                  : $r('sys.symbol.checkmark_circle'))
                  .fontSize(14)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme)])
                Text(this.areAllSectionBucketsSelected(section.id) ? '取消本组选择' : '选中本组')
                  .fontSize(13)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
              }
            }
              .height(36)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
              .borderRadius(10)
              .onClick(() => {
                this.toggleSectionSelection(section.id);
              })
          }

          Column({ space: 0 }) {
            ForEach(this.getSectionBuckets(section.id), (bucket: StorageBucketSummary, index: number) => {
              this.buildBucketRow(bucket, index === this.getSectionLastIndex(section.id))
            }, (bucket: StorageBucketSummary) => `${bucket.id}_${this.snapshotRenderVersion}_${this.isBucketSelected(bucket.id) ? 'selected' : 'idle'}`)
          }
          .width('100%')
        }
        .width('100%')
        .transition(
          TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut })
            .combine(TransitionEffect.translate({ y: -10 }).animation({ duration: 220, curve: Curve.EaseOut }))
        )
      }
    }
    .width('100%')
    .padding(18)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .key(
      `storage_section_${section.id}_${this.snapshotRenderVersion}_${section.totalSizeBytes}_${section.clearableSizeBytes}_` +
      `${this.isSectionExpanded(section.id) ? 'expanded' : 'collapsed'}_${this.getSectionSelectedCount(section.id)}`
    )
  }

  @Builder
  private buildLoadingState() {
    Column({ space: 18 }) {
      LoadingProgress()
        .width(38)
        .height(38)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

      Text('正在扫描存储目录...')
        .fontSize(15)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private buildErrorState() {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
        .fontSize(28)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)])

      Text(this.errorMessage.length > 0 ? this.errorMessage : '存储信息加载失败')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .textAlign(TextAlign.Center)

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(15)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)])
          Text('重新扫描')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        }
      }
        .height(42)
        .padding({ left: 18, right: 18 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_primary', this.themeState.currentTheme))
        .borderRadius(12)
        .onClick(() => {
          this.invalidateSilentRefreshSequence();
          void this.loadSnapshot(true, false);
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private buildContent(snapshot: StorageDashboardSnapshot) {
    Scroll() {
      Column({ space: 16 }) {
        Blank()
          .height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))

        this.buildOverviewPanel(snapshot)
        this.buildActionPanel()

        ForEach(snapshot.sections, (section: StorageSectionSummary) => {
          this.buildSectionPanel(section)
        }, (section: StorageSectionSummary) => `${section.id}_${this.snapshotRenderVersion}_${this.isSectionExpanded(section.id) ? 'expanded' : 'collapsed'}_${this.getSectionSelectedCount(section.id)}`)

        Blank()
          .height(24 + this.navigationBarHeight)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8 })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .key(`storage_content_${this.snapshotRenderVersion}_${this.isRefreshing ? 'refreshing' : 'idle'}`)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
  }

  build() {
    HdsNavDestination() {
      Stack() {
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Column() {
          if (this.isLoading && !this.hasLoaded) {
            Blank()
              .height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
            this.buildLoadingState()
          } else if (this.snapshot) {
            this.buildContent(this.snapshot as StorageDashboardSnapshot)
          } else {
            Blank()
              .height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
            this.buildErrorState()
          }
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .key(`storage_page_root_${this.snapshotRenderVersion}_${this.hasLoaded ? 'loaded' : 'loading'}`)

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '存储管理',
          appFontFamily: this.appFontFamily,
          actions: this.getTitleBarActions()
        })
      }
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor(Color.Transparent)
  }
}
