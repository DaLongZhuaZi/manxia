import { HdsNavDestination } from '@kit.UIDesignKit';
import { common } from '@kit.AbilityKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { FontAwareHelper, FontAwareState } from 'manxia_theme/src/main/ets/Framework/Components/FontAware';
import { ThemeAwareHelper, ThemeAwareState } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import {
  StorageBucketId,
  StorageBucketSummary,
  StorageClearResult,
  StorageDashboardService,
  StorageDashboardSnapshot,
  StorageProviderStatusSummary,
  StorageSectionId,
  StorageSectionSummary
} from '../Framework/Storage/StorageDashboardService';
import { StorageOperationRecord } from '../Framework/Storage/StorageUsageMonitor';
import { getHelpPanelManagerV2 } from '../Framework/Components/HelpPanelV2';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsImmersiveTitleActionItem, SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';

const TAG = 'StorageManagementPage';
const STORAGE_AUTO_REFRESH_INTERVAL_MS: number = 3500;

enum StorageConsoleTab {
  CACHE = 'CACHE',
  OFFLINE = 'OFFLINE',
  DATA = 'DATA',
  TASKS = 'TASKS'
}

class StorageTargetNavigationParam {
  public fromPage: string = 'StorageManagementPage';
  public storageEntryId: string = '';
  public timestamp: number = 0;
}

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
  @State private searchKeyword: string = '';
  @State private selectedConsoleTab: StorageConsoleTab = StorageConsoleTab.CACHE;
  @State private collapsedSectionIds: StorageSectionId[] = [
    StorageSectionId.USER_DATA,
    StorageSectionId.BACKUP,
    StorageSectionId.EXTENSION,
    StorageSectionId.PROTECTED
  ];

  private readonly storageService: StorageDashboardService = StorageDashboardService.getInstance();
  private readonly componentId: string = TAG;
  private silentRefreshSequenceToken: number = 0;
  private pendingSilentRefreshTimers: number[] = [];
  private pendingOptimisticBucketIds: StorageBucketId[] = [];
  private refreshTimer: number = -1;
  private isSnapshotRefreshRunning: boolean = false;
  private snapshotRefreshGeneration: number = 0;
  private snapshotRenderVersion: number = 0;
  private readonly consoleTabs: StorageConsoleTab[] = [
    StorageConsoleTab.CACHE,
    StorageConsoleTab.OFFLINE,
    StorageConsoleTab.DATA,
    StorageConsoleTab.TASKS
  ];

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
    if (this.hasLoaded && this.isSameSnapshotContent(this.snapshot, snapshot)) {
      logger.debug(TAG, '存储快照内容未变化，跳过UI提交');
      return;
    }
    this.snapshot = snapshot;
    this.snapshotRenderVersion += 1;
    logger.debug(
      TAG,
      `提交存储快照: version=${this.snapshotRenderVersion}, scanned=${snapshot.overview.scannedTotalSizeBytes}, cleanable=${snapshot.overview.cleanableTotalSizeBytes}, selected=${this.selectedBucketIds.length}, updatedAt=${snapshot.overview.updatedAt}`
    );
  }

  private isSameSnapshotContent(current: StorageDashboardSnapshot | null, next: StorageDashboardSnapshot): boolean {
    if (!current) {
      return false;
    }
    if (current.buckets.length !== next.buckets.length ||
      current.sections.length !== next.sections.length ||
      current.providerStatuses.length !== next.providerStatuses.length ||
      current.operationRecords.length !== next.operationRecords.length) {
      return false;
    }
    if (current.overview.scannedTotalSizeBytes !== next.overview.scannedTotalSizeBytes ||
      current.overview.cleanableTotalSizeBytes !== next.overview.cleanableTotalSizeBytes ||
      current.overview.dangerTotalSizeBytes !== next.overview.dangerTotalSizeBytes ||
      current.overview.protectedTotalSizeBytes !== next.overview.protectedTotalSizeBytes ||
      current.overview.memorySizeBytes !== next.overview.memorySizeBytes ||
      current.overview.failedProviderCount !== next.overview.failedProviderCount) {
      return false;
    }
    for (let index = 0; index < current.buckets.length; index++) {
      const left = current.buckets[index];
      const right = next.buckets[index];
      if (left.id !== right.id ||
        left.sizeBytes !== right.sizeBytes ||
        left.itemCount !== right.itemCount ||
        left.isClearable !== right.isClearable ||
        left.risk !== right.risk) {
        return false;
      }
    }
    for (let index = 0; index < current.providerStatuses.length; index++) {
      const left = current.providerStatuses[index];
      const right = next.providerStatuses[index];
      if (left.providerId !== right.providerId ||
        left.success !== right.success ||
        left.message !== right.message) {
        return false;
      }
    }
    return true;
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
    } else if (showRefreshToast) {
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
      if (bucket && this.isBucketActionable(bucket) && this.isBucketVisibleInCurrentTab(bucket)) {
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

  private openBucketTargetPage(bucket: StorageBucketSummary): void {
    if (bucket.targetPage.length <= 0) {
      this.showToast('该项暂无专职管理页面');
      return;
    }
    try {
      const stack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (!stack) {
        this.showToast('当前无法打开目标页面');
        return;
      }
      const navParam = new StorageTargetNavigationParam();
      navParam.storageEntryId = bucket.id;
      navParam.timestamp = Date.now();
      stack.pushPathByName(bucket.targetPage, navParam);
      logger.info(TAG, `从存储总控跳转: target=${bucket.targetPage}, entry=${bucket.id}`);
    } catch (error) {
      logger.error(TAG, `打开存储条目目标页面失败: ${bucket.targetPage}, ${String(error)}`);
      this.showToast('打开目标页面失败');
    }
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

  private containsSectionId(sectionIds: StorageSectionId[], sectionId: StorageSectionId): boolean {
    for (let index = 0; index < sectionIds.length; index++) {
      if (sectionIds[index] === sectionId) {
        return true;
      }
    }
    return false;
  }

  private getNormalizedSearchKeyword(): string {
    return this.searchKeyword.trim().toLowerCase();
  }

  private doesBucketMatchSearch(bucket: StorageBucketSummary): boolean {
    const keyword = this.getNormalizedSearchKeyword();
    if (keyword.length <= 0) {
      return true;
    }
    return bucket.title.toLowerCase().includes(keyword) ||
      bucket.subtitle.toLowerCase().includes(keyword) ||
      bucket.note.toLowerCase().includes(keyword) ||
      bucket.path.toLowerCase().includes(keyword);
  }

  private isSectionInConsoleTab(sectionId: StorageSectionId, tab: StorageConsoleTab): boolean {
    switch (tab) {
      case StorageConsoleTab.CACHE:
        return sectionId === StorageSectionId.SAFE_CACHE ||
          sectionId === StorageSectionId.TEMP_WORKSPACE ||
          sectionId === StorageSectionId.RUNTIME_MEMORY;
      case StorageConsoleTab.OFFLINE:
        return sectionId === StorageSectionId.OFFLINE_CACHE ||
          sectionId === StorageSectionId.DOWNLOAD_EXTERNAL;
      case StorageConsoleTab.DATA:
        return sectionId === StorageSectionId.USER_DATA ||
          sectionId === StorageSectionId.BACKUP ||
          sectionId === StorageSectionId.EXTENSION ||
          sectionId === StorageSectionId.LOGS ||
          sectionId === StorageSectionId.PROTECTED;
      case StorageConsoleTab.TASKS:
      default:
        return false;
    }
  }

  private isBucketVisibleInCurrentTab(bucket: StorageBucketSummary): boolean {
    if (!this.isSectionInConsoleTab(bucket.section, this.selectedConsoleTab)) {
      return false;
    }
    return this.doesBucketMatchSearch(bucket);
  }

  private selectConsoleTab(tab: StorageConsoleTab): void {
    if (this.selectedConsoleTab === tab) {
      return;
    }
    this.selectedConsoleTab = tab;
    this.trimSelection();
  }

  private getVisibleSections(snapshot: StorageDashboardSnapshot): StorageSectionSummary[] {
    const sections: StorageSectionSummary[] = [];
    if (this.selectedConsoleTab === StorageConsoleTab.TASKS) {
      return sections;
    }
    for (let index = 0; index < snapshot.sections.length; index++) {
      const section = snapshot.sections[index];
      if (this.isSectionInConsoleTab(section.id, this.selectedConsoleTab) && this.getSectionBuckets(section.id).length > 0) {
        sections.push(section);
      }
    }
    return sections;
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
      if (this.isBucketActionable(bucket) && this.isBucketVisibleInCurrentTab(bucket)) {
        buckets.push(bucket);
      }
    }
    return buckets;
  }

  private getAutoClearEligibleCount(): number {
    let count = 0;
    const snapshot = this.snapshot;
    if (!snapshot) {
      return count;
    }
    for (let index = 0; index < snapshot.buckets.length; index++) {
      if (snapshot.buckets[index].autoClearEligible) {
        count += 1;
      }
    }
    return count;
  }

  private getRuntimeMemorySize(): number {
    let sizeBytes = 0;
    const snapshot = this.snapshot;
    if (!snapshot) {
      return sizeBytes;
    }
    for (let index = 0; index < snapshot.buckets.length; index++) {
      const bucket = snapshot.buckets[index];
      if (bucket.section === StorageSectionId.RUNTIME_MEMORY) {
        sizeBytes += bucket.sizeBytes;
      }
    }
    return sizeBytes;
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

    if (!this.isSectionInConsoleTab(sectionId, this.selectedConsoleTab)) {
      return buckets;
    }
    for (let index = 0; index < snapshot.buckets.length; index++) {
      const bucket = snapshot.buckets[index];
      if (bucket.section === sectionId && this.doesBucketMatchSearch(bucket)) {
        buckets.push(bucket);
      }
    }
    return buckets;
  }

  private isSectionExpanded(sectionId: StorageSectionId): boolean {
    return !this.containsSectionId(this.collapsedSectionIds, sectionId);
  }

  private setSectionExpanded(sectionId: StorageSectionId, expanded: boolean): void {
    const nextCollapsed: StorageSectionId[] = [];
    for (let index = 0; index < this.collapsedSectionIds.length; index++) {
      const currentId = this.collapsedSectionIds[index];
      if (currentId !== sectionId) {
        nextCollapsed.push(currentId);
      }
    }
    if (!expanded && !this.containsSectionId(nextCollapsed, sectionId)) {
      nextCollapsed.push(sectionId);
    }
    this.collapsedSectionIds = nextCollapsed;
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

    const hasDangerTarget = this.hasDangerBuckets(clearTargets);
    this.getUIContext().showAlertDialog({
      title: '确认清理',
      message: `${previewLines.join('\n\n')}\n\n总计 ${this.storageService.formatSize(totalSizeBytes)} · ${totalItems} 项\n${hasDangerTarget ? '其中包含高风险数据，下一步还需要再次确认。' : '此操作会直接删除对应缓存文件，部分离线内容稍后需要重新拉取。'}`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: hasDangerTarget ? '继续确认' : '开始清理',
        action: () => {
          if (hasDangerTarget) {
            this.showDangerClearConfirmDialog(bucketIds, totalSizeBytes, totalItems);
            return;
          }
          void this.performClear(bucketIds);
        }
      }
    });
  }

  private hasDangerBuckets(buckets: StorageBucketSummary[]): boolean {
    for (let index = 0; index < buckets.length; index++) {
      if (buckets[index].risk === 'danger') {
        return true;
      }
    }
    return false;
  }

  private showDangerClearConfirmDialog(bucketIds: StorageBucketId[], totalSizeBytes: number, totalItems: number): void {
    const dangerTitles: string[] = [];
    for (let index = 0; index < bucketIds.length; index++) {
      const bucket = this.findBucketById(bucketIds[index]);
      if (bucket && bucket.risk === 'danger') {
        dangerTitles.push(bucket.title);
      }
    }

    this.getUIContext().showAlertDialog({
      title: '高风险清理确认',
      message: `将清理 ${this.storageService.formatSize(totalSizeBytes)} · ${totalItems} 项。\n高风险项：${dangerTitles.join('、')}\n这些内容删除后可能需要重新同步、重新导入或重新生成。`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '确认清理',
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
      case 'external':
        return '外部缓存';
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
      case 'external':
        return '外部';
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
        return $r('sys.symbol.download');
      case 'external':
        return $r('sys.symbol.wifi_router');
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

  private getSectionSelectionSymbol(sectionId: StorageSectionId): Resource {
    if (!this.hasSectionSelectableBuckets(sectionId)) {
      return $r('sys.symbol.lock');
    }
    if (this.areAllSectionBucketsSelected(sectionId)) {
      return $r('sys.symbol.checkmark_circle_fill');
    }
    if (this.getSectionSelectedCount(sectionId) > 0) {
      return $r('sys.symbol.minus_circle_fill');
    }
    return $r('sys.symbol.circle');
  }

  private getSectionSelectionColor(sectionId: StorageSectionId): Resource {
    if (!this.hasSectionSelectableBuckets(sectionId)) {
      return ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme);
    }
    if (this.areAllSectionBucketsSelected(sectionId) || this.getSectionSelectedCount(sectionId) > 0) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme);
    }
    return ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme);
  }

  private getRiskBadgeBackground(bucket: StorageBucketSummary): Resource {
    switch (bucket.risk) {
      case 'caution':
        return ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme);
      case 'danger':
        return ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme);
      case 'protected':
        return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme);
      default:
        return ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme);
    }
  }

  private getRiskBadgeText(bucket: StorageBucketSummary): string {
    switch (bucket.risk) {
      case 'caution':
        return '需确认';
      case 'danger':
        return '高风险';
      case 'protected':
        return '受保护';
      default:
        return '可回收';
    }
  }

  private getBucketProgressColor(bucket: StorageBucketSummary): Resource {
    switch (bucket.risk) {
      case 'caution':
        return ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme);
      case 'danger':
        return ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme);
      case 'protected':
        return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme);
      default:
        return ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme);
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

  private formatDurationMs(durationMs: number): string {
    if (durationMs < 1000) {
      return `${durationMs}ms`;
    }
    return `${(durationMs / 1000).toFixed(1)}s`;
  }

  private getProviderStatusSymbol(status: StorageProviderStatusSummary): Resource {
    return status.success ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.exclamationmark_triangle_fill');
  }

  private getProviderStatusColor(status: StorageProviderStatusSummary): Resource {
    return status.success
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
      : ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme);
  }

  private getOperationRecordSymbol(record: StorageOperationRecord): Resource {
    return record.success ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.exclamationmark_triangle_fill');
  }

  private getOperationRecordColor(record: StorageOperationRecord): Resource {
    return record.success
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
      : ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme);
  }

  private getSecondaryButtonBackground(): Resource {
    return ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme);
  }

  private getSecondaryButtonTextColor(): Resource {
    return ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme);
  }

  private getSecondaryButtonBorderColor(): Resource {
    return ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme);
  }

  private getDisabledButtonTextColor(): Resource {
    return ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme);
  }

  private hasSelectedBuckets(): boolean {
    return this.selectedBucketIds.length > 0;
  }

  private getClearButtonBackground(): Resource {
    return this.hasSelectedBuckets()
      ? ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme)
      : ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme);
  }

  private getClearButtonTextColor(): Resource {
    return this.hasSelectedBuckets()
      ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)
      : this.getDisabledButtonTextColor();
  }

  private getConsoleTabTitle(tab: StorageConsoleTab): string {
    switch (tab) {
      case StorageConsoleTab.CACHE:
        return '缓存';
      case StorageConsoleTab.OFFLINE:
        return '离线';
      case StorageConsoleTab.DATA:
        return '数据';
      case StorageConsoleTab.TASKS:
      default:
        return '记录';
    }
  }

  private getConsoleTabSubtitle(tab: StorageConsoleTab): string {
    switch (tab) {
      case StorageConsoleTab.CACHE:
        return '安全缓存与临时工作区';
      case StorageConsoleTab.OFFLINE:
        return '离线阅读和远程库缓存';
      case StorageConsoleTab.DATA:
        return '备份、扩展、日志和受保护项';
      case StorageConsoleTab.TASKS:
      default:
        return '扫描结果和清理历史';
    }
  }

  private getConsoleTabItemCount(snapshot: StorageDashboardSnapshot, tab: StorageConsoleTab): number {
    if (tab === StorageConsoleTab.TASKS) {
      return snapshot.providerStatuses.length + snapshot.operationRecords.length;
    }
    let count = 0;
    for (let index = 0; index < snapshot.buckets.length; index++) {
      if (this.isSectionInConsoleTab(snapshot.buckets[index].section, tab)) {
        count += 1;
      }
    }
    return count;
  }

  private getConsoleTabSize(snapshot: StorageDashboardSnapshot, tab: StorageConsoleTab): number {
    let sizeBytes = 0;
    if (tab === StorageConsoleTab.TASKS) {
      return sizeBytes;
    }
    for (let index = 0; index < snapshot.buckets.length; index++) {
      const bucket = snapshot.buckets[index];
      if (this.isSectionInConsoleTab(bucket.section, tab)) {
        sizeBytes += bucket.sizeBytes;
      }
    }
    return sizeBytes;
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
      const selectedLabel = section.id === StorageSectionId.RUNTIME_MEMORY ? '已选释放' : '已选清理';
      const baseLabel = section.id === StorageSectionId.RUNTIME_MEMORY ? '当前占用' : '可回收';
      return `${selectedLabel} ${this.storageService.formatSize(selectedSizeBytes)} · ${baseLabel} ${this.storageService.formatSize(section.clearableSizeBytes)} · ${selectedCount} 项`;
    }

    if (section.id === StorageSectionId.RUNTIME_MEMORY) {
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
    const helpContent = `# 数据与缓存管理帮助

## 这个页面会展示什么

- **应用总占用**：系统统计口径下的应用整体空间
- **缓存与临时工作区**：可安全回收的缓存、偏好缓存、网络文件夹缓存和临时处理目录
- **离线与数据**：漫画、小说、备份、扩展仓库、导入文件、封面、字体和日志
- **任务/记录**：最近一次 provider 扫描结果、失败项和最近清理记录
- **受保护数据**：数据库、导入文件、插件等缺少一致性删除服务的数据，只展示和跳转

## 清理逻辑

- 页面通过统一 provider 递归扫描目录，而不是只看顶层文件
- 对图源内容缓存、Tab 持久缓存会读取 Preferences 中的实际内容
- 对封面缓存和永久图片缓存，清理时会同步重置对应数据库状态
- 高风险数据必须二次确认；没有一致性删除能力的数据不会开放直接清理

## 使用建议

- 想要快速瘦身，先看“缓存”和“临时工作区”
- 想要腾出更多空间，再看“离线”“备份”“扩展”和“日志与诊断”
- 如果你依赖小说离线、Komga 或 Suwayomi，本页会明确标出风险提示

## 注意

- 本页不会删除书架、阅读记录、插件和数据库
- Download 同步目录未连接时，相关条目会显示但不会误删外部内容`;

    getHelpPanelManagerV2().showInlineHelp('数据与缓存管理帮助', helpContent);
  }

  @Builder
  private buildMetricCell(label: string, value: string, note: string) {
    Column({ space: 3 }) {
      Text(label)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

      Text(value)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(note)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildConsoleTabPanel(snapshot: StorageDashboardSnapshot) {
    Row({ space: 8 }) {
      ForEach(this.consoleTabs, (tab: StorageConsoleTab) => {
        this.buildConsoleTabButton(snapshot, tab)
      }, (tab: StorageConsoleTab) => tab)
    }
    .width('100%')
    .padding(6)
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
    .borderRadius(18)
  }

  @Builder
  private buildConsoleTabButton(snapshot: StorageDashboardSnapshot, tab: StorageConsoleTab) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Column({ space: 2 }) {
        Text(this.getConsoleTabTitle(tab))
          .fontSize(13)
          .fontWeight(this.selectedConsoleTab === tab ? FontWeight.Bold : FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(this.selectedConsoleTab === tab
            ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(tab === StorageConsoleTab.TASKS
          ? `${this.getConsoleTabItemCount(snapshot, tab)} 项`
          : this.storageService.formatSize(this.getConsoleTabSize(snapshot, tab)))
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor(this.selectedConsoleTab === tab
            ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
      .layoutWeight(1)
      .height(52)
      .backgroundColor(this.selectedConsoleTab === tab
        ? ThemeAwareHelper.getTestManagementThemedColor('button_primary', this.themeState.currentTheme)
        : Color.Transparent)
      .borderRadius(12)
      .onClick(() => {
        this.selectConsoleTab(tab);
      })
  }

  @Builder
  private buildOverviewPanel(snapshot: StorageDashboardSnapshot) {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.externaldrive'))
          .fontSize(20)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])

        Column({ space: 4 }) {
          Text('数据与缓存总览')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(`已更新 ${this.formatUpdatedAt(snapshot.overview.updatedAt)} · 设备剩余 ${this.storageService.formatSize(snapshot.overview.deviceFreeSizeBytes)} · Provider失败 ${snapshot.overview.failedProviderCount} 个`)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
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

      Row({ space: 16 }) {
        this.buildMetricCell('可回收空间', this.storageService.formatSize(snapshot.overview.cleanableTotalSizeBytes), `${this.getClearableBuckets().length} 项当前可清理`)
        this.buildMetricCell('高风险数据', this.storageService.formatSize(snapshot.overview.dangerTotalSizeBytes), '需要二次确认')
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
    }
    .width('100%')
    .padding(14)
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
  }

  @Builder
  private buildControlPanel() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(16)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])

        TextInput({ placeholder: '搜索数据、缓存或路径', text: this.searchKeyword })
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .borderRadius(12)
          .onChange((value: string) => {
            this.searchKeyword = value;
            this.trimSelection();
          })

        if (this.searchKeyword.length > 0) {
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
              .fontSize(18)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
          }
            .width(40)
            .height(40)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
            .borderRadius(12)
            .onClick(() => {
              this.searchKeyword = '';
              this.trimSelection();
            })
        }
      }
      .width('100%')

      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(this.hasSelectedBuckets() ? `已选择 ${this.selectedBucketIds.length} 项` : '未选择清理项')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.hasSelectedBuckets()
            ? `预计释放 ${this.storageService.formatSize(this.getSelectedSizeBytes())}`
            : (this.searchKeyword.length > 0
              ? `显示 ${this.getClearableBuckets().length} 项可清理结果`
              : `可清理 ${this.getClearableBuckets().length} 项 · 自动候选 ${this.getAutoClearEligibleCount()} 项 · 内存 ${this.storageService.formatSize(this.getRuntimeMemorySize())}`))
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(16)
            .fontColor([this.getSecondaryButtonTextColor()])
        }
          .width(38)
          .height(38)
          .enabled(!this.isLoading && !this.isClearing)
          .backgroundColor(this.getSecondaryButtonBackground())
          .border({ width: 1, color: this.getSecondaryButtonBorderColor() })
          .borderRadius(12)
          .onClick(() => {
            void this.refreshSnapshot();
          })

        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Row({ space: 6 }) {
            SymbolGlyph(this.areAllClearableBucketsSelected()
              ? $r('sys.symbol.minus_circle_fill')
              : $r('sys.symbol.checkmark_circle'))
              .fontSize(14)
              .fontColor([this.getClearableBuckets().length > 0 ? this.getSecondaryButtonTextColor() : this.getDisabledButtonTextColor()])
            Text(this.areAllClearableBucketsSelected() ? '取消全选' : '全选可清理')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(this.getClearableBuckets().length > 0 ? this.getSecondaryButtonTextColor() : this.getDisabledButtonTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .justifyContent(FlexAlign.Center)
          .width('100%')
        }
          .width(106)
          .height(38)
          .enabled(!this.isLoading && !this.isClearing && this.getClearableBuckets().length > 0)
          .backgroundColor(this.getSecondaryButtonBackground())
          .border({ width: 1, color: this.getSecondaryButtonBorderColor() })
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
            .fontColor([this.getClearButtonTextColor()])
          Text(this.isClearing ? '清理中...' : this.getSelectedActionLabel())
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getClearButtonTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')
      }
        .width('100%')
        .height(42)
        .enabled(this.selectedBucketIds.length > 0 && !this.isClearing)
        .backgroundColor(this.getClearButtonBackground())
        .border({ width: 1, color: this.getSecondaryButtonBorderColor() })
        .borderRadius(12)
        .onClick(() => {
          this.showClearConfirmDialog(this.selectedBucketIds);
        })
    }
    .width('100%')
    .padding(14)
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
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(`${bucket.itemCount} ${bucket.itemLabel}`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(this.getPathKindLabel(bucket))
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
              .borderRadius(999)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
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

          if (bucket.targetPage.length > 0) {
            Button({ type: ButtonType.Normal, stateEffect: true }) {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.arrow_up_right'))
                  .fontSize(12)
                  .fontColor([this.getSecondaryButtonTextColor()])
                Text('前往')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.getSecondaryButtonTextColor())
                  .maxLines(1)
              }
            }
              .height(32)
              .padding({ left: 12, right: 12 })
              .backgroundColor(this.getSecondaryButtonBackground())
              .border({ width: 1, color: this.getSecondaryButtonBorderColor() })
              .borderRadius(10)
              .alignSelf(ItemAlign.Start)
              .onClick(() => {
                this.openBucketTargetPage(bucket);
              })
          }

          Progress({
            value: bucket.progressRatio > 0 ? bucket.progressRatio : 0,
            total: 1,
            type: ProgressType.Linear
          })
            .width('100%')
            .height(6)
            .color(this.getBucketProgressColor(bucket))
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
      Row({ space: 10 }) {
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph(this.getSectionSelectionSymbol(section.id))
            .fontSize(24)
            .fontColor([this.getSectionSelectionColor(section.id)])
        }
          .width(40)
          .height(40)
          .enabled(this.hasSectionSelectableBuckets(section.id))
          .backgroundColor(Color.Transparent)
          .borderRadius(999)
          .onClick(() => {
            this.toggleSectionSelection(section.id);
          })

        Row({ space: 12 }) {
          Column({ space: 4 }) {
            Text(section.title)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

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
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(this.getSectionSummaryMetaText(section))
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(this.getSectionHeaderMetaColor(section.id))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.End)

          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(16)
            .fontColor([this.getSectionHeaderMetaColor(section.id)])
            .rotate({ angle: this.isSectionExpanded(section.id) ? 0 : -90 })
            .animation({ duration: 220, curve: Curve.EaseInOut })
        }
          .layoutWeight(1)
          .onClick(() => {
            this.toggleSectionExpanded(section.id);
          })
      }
      .width('100%')
      .padding({ left: 12, right: 14, top: 12, bottom: 12 })
      .backgroundColor(this.getSectionHeaderBackground(section.id))
      .border({
        width: 1,
        color: this.getSectionHeaderBorderColor(section.id)
      })
      .borderRadius(16)
      .animation({ duration: 220, curve: Curve.EaseInOut })
      .alignItems(VerticalAlign.Center)

      if (this.isSectionExpanded(section.id)) {
        Column({ space: 14 }) {
          Column({ space: 0 }) {
            ForEach(this.getSectionBuckets(section.id), (bucket: StorageBucketSummary, index: number) => {
              this.buildBucketRow(bucket, index === this.getSectionLastIndex(section.id))
            }, (bucket: StorageBucketSummary) => `${bucket.id}`)
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
  }

  @Builder
  private buildTaskPanel(snapshot: StorageDashboardSnapshot) {
    Column({ space: 16 }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.list_bullet'))
          .fontSize(18)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])

        Column({ space: 4 }) {
          Text('任务/记录')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          Text(`最近扫描 ${snapshot.providerStatuses.length} 个 provider · 历史趋势 ${snapshot.trend.length} 条`)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      Column({ space: 10 }) {
        ForEach(snapshot.providerStatuses, (status: StorageProviderStatusSummary) => {
          Row({ space: 10 }) {
            SymbolGlyph(this.getProviderStatusSymbol(status))
              .fontSize(16)
              .fontColor([this.getProviderStatusColor(status)])

            Column({ space: 3 }) {
              Text(status.title)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Text(status.success
                ? `扫描完成 · ${this.formatDurationMs(status.durationMs)}`
                : `扫描失败 · ${status.message}`)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .borderRadius(12)
        }, (status: StorageProviderStatusSummary) => `${status.providerId}_${status.success ? 'ok' : 'fail'}_${status.durationMs}`)
      }
      .width('100%')

      if (snapshot.operationRecords.length > 0) {
        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))

        Column({ space: 10 }) {
          ForEach(snapshot.operationRecords, (record: StorageOperationRecord) => {
            Row({ space: 10 }) {
              SymbolGlyph(this.getOperationRecordSymbol(record))
                .fontSize(16)
                .fontColor([this.getOperationRecordColor(record)])

              Column({ space: 3 }) {
                Text(`${record.title} · ${this.formatUpdatedAt(record.timestamp)}`)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

                Text(`${this.storageService.formatSize(record.sizeBytes)} · ${record.detail}`)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
            .borderRadius(12)
          }, (record: StorageOperationRecord) => `${record.timestamp}_${record.title}_${record.sizeBytes}`)
        }
        .width('100%')
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
        this.buildConsoleTabPanel(snapshot)

        if (this.selectedConsoleTab === StorageConsoleTab.TASKS) {
          this.buildTaskPanel(snapshot)
        } else {
          this.buildControlPanel()

          ForEach(this.getVisibleSections(snapshot), (section: StorageSectionSummary) => {
            this.buildSectionPanel(section)
          }, (section: StorageSectionSummary) => `${section.id}`)
        }

        Blank()
          .height(24 + this.navigationBarHeight)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8 })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
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

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '数据与缓存管理',
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
