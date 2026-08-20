// 文件路径: entry/src/main/ets/pages/VersionHistoryPage.ets
/**
 * 版本记录页面
 * 展示漫匣与漫匣图源仓库提交记录，支持展开详情与文件增删统计
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from 'manxia_theme/src/main/ets/Framework/Components/FontAware';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from 'manxia_theme/src/main/ets/Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from 'manxia_core/src/main/ets/Framework/Utils/ResponsiveLayout';
import { TimeUtils } from 'manxia_core/src/main/ets/Framework/Utils/TimeUtils';
import {
  getVersionHistoryManager,
  VersionCommitRecord,
  VersionCommitDetail,
  VersionCommitFileChange,
  VersionCommitRepositoryTarget,
  VersionCommitRepositoryResult,
  DEFAULT_VERSION_COMMIT_REPOSITORIES,
  DEFAULT_VERSION_COMMIT_FETCH_LIMIT
} from 'manxia_core/src/main/ets/Framework/Managers/VersionHistoryManager';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';

const TAG = 'VersionHistoryPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;
const MANXIA_REPO_KEY = 'manxia';
const MANXIA_EXT_REPO_KEY = 'manxia_extensions';

interface NavDestinationContext {
  pathStack: NavPathStack;
}

@Component
struct VersionHistoryPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  private scroller: Scroller = new Scroller();

  // 主题/字体状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private componentId: string = 'VersionHistoryPage';

  // 响应式布局状态
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;

  // 页面状态
  @State private isLoading: boolean = true;
  @State private isRefreshing: boolean = false;
  @State private manxiaResult: VersionCommitRepositoryResult | null = null;
  @State private manxiaExtensionResult: VersionCommitRepositoryResult | null = null;
  @State private showManxiaCachedHistory: boolean = false;
  @State private showExtensionCachedHistory: boolean = false;
  @State private expandedCommitKeys: string[] = [];
  @State private lastRefreshAt: number = 0;

  private versionHistoryManager = getVersionHistoryManager();
  private lifecycle = new PageLifecycleManager('VersionHistoryPage', { enableDebug: true });

  onPageShow(): void {
    try {
      const stack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (stack) {
        this.pathStack = stack;
      }
    } catch (error) {
      logger.warn(TAG, `读取 GlobalNavStack 失败: ${String(error)}`);
    }
  }

  async onReady(): Promise<void> {
    ThemeAwareHelper.initializeThemeAware(
      this.componentId,
      this.themeState,
      (newTheme: ThemeType) => {
        logger.info(TAG, `主题切换到: ${newTheme}`);
      }
    );

    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );

    this.initializeResponsiveLayout();
    await this.initializeData();
  }

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
    this.updateResponsiveParams();
    this.deviceChangeListener = (_deviceInfo: DeviceInfo) => {
      this.updateResponsiveParams();
    };
    this.deviceManager.addListener(this.deviceChangeListener);
  }

  private updateResponsiveParams(): void {
    const layoutParams = ResponsiveLayoutHelper.getLayoutParams();
    const deviceInfo = this.deviceManager.getDeviceInfo();
    this.responsive_contentPadding = layoutParams.contentPadding;

    switch (deviceInfo.breakpoint) {
      case Breakpoint.XS:
        this.responsive_maxContentWidth = 640;
        break;
      case Breakpoint.SM:
        this.responsive_maxContentWidth = 840;
        break;
      case Breakpoint.MD:
        this.responsive_maxContentWidth = 1024;
        break;
      case Breakpoint.LG:
        this.responsive_maxContentWidth = 1200;
        break;
    }
  }

  private async initializeData(): Promise<void> {
    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      await this.versionHistoryManager.initialize(context);
      await this.refreshCommitHistory(true);
    } catch (error) {
      logger.error(TAG, `初始化版本记录失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({
        message: '初始化版本记录失败',
        duration: 2500
      });
      this.isLoading = false;
    }
  }

  private async refreshCommitHistory(showLoading: boolean = false): Promise<void> {
    if (this.isRefreshing) {
      return;
    }

    if (showLoading) {
      this.isLoading = true;
    }
    this.isRefreshing = true;

    try {
      const results = await this.versionHistoryManager.refreshRepositories(
        DEFAULT_VERSION_COMMIT_REPOSITORIES,
        DEFAULT_VERSION_COMMIT_FETCH_LIMIT
      );

      this.manxiaResult = results.find((result: VersionCommitRepositoryResult) => result.key === MANXIA_REPO_KEY) || null;
      this.manxiaExtensionResult = results.find((result: VersionCommitRepositoryResult) => result.key === MANXIA_EXT_REPO_KEY) || null;
      this.expandedCommitKeys = [];
      this.lastRefreshAt = Date.now();
    } catch (error) {
      logger.error(TAG, `刷新版本记录失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({
        message: '刷新失败，请稍后重试',
        duration: 2500
      });
    } finally {
      this.isRefreshing = false;
      this.isLoading = false;
    }
  }

  private getCommitStatusText(result: VersionCommitRepositoryResult): string {
    if (result.networkUpdated && result.usedProxy) {
      return '已通过加速代理更新';
    }
    if (result.networkUpdated) {
      return '已通过直连更新';
    }
    if (result.usingCache) {
      return '网络不可用，使用本地缓存';
    }
    return '未获取到提交记录';
  }

  private formatRefreshTime(timestamp: number): string {
    if (timestamp <= 0) {
      return '未知';
    }
    return TimeUtils.formatDisplay(timestamp, 'datetime');
  }

  private formatCommitTime(timestamp: number): string {
    if (timestamp <= 0) {
      return '未知时间';
    }
    const relativeText = TimeUtils.getRelativeTime(timestamp);
    const absoluteText = TimeUtils.formatDisplay(timestamp, 'datetime');
    return `${relativeText} · ${absoluteText}`;
  }

  private async openExternalUrl(url: string): Promise<void> {
    if (!url) {
      return;
    }
    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      await context.openLink(url, { appLinkingOnly: false });
    } catch (error) {
      logger.error(TAG, `打开链接失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({
        message: '无法打开链接，请稍后重试',
        duration: 2000
      });
    }
  }

  private getVisibleCommits(
    result: VersionCommitRepositoryResult,
    showCachedHistory: boolean
  ): VersionCommitRecord[] {
    const visibleCount = showCachedHistory
      ? result.commits.length
      : Math.min(result.commits.length, DEFAULT_VERSION_COMMIT_FETCH_LIMIT);
    return result.commits.slice(0, visibleCount);
  }

  private getCommitExpandKey(repoKey: string, sha: string): string {
    return `${repoKey}:${sha}`;
  }

  private isCommitExpanded(repoKey: string, sha: string): boolean {
    return this.expandedCommitKeys.includes(this.getCommitExpandKey(repoKey, sha));
  }

  private setCommitExpanded(repoKey: string, sha: string, expanded: boolean): void {
    const key = this.getCommitExpandKey(repoKey, sha);
    if (expanded) {
      if (!this.expandedCommitKeys.includes(key)) {
        this.expandedCommitKeys = this.expandedCommitKeys.concat([key]);
      }
      return;
    }
    this.expandedCommitKeys = this.expandedCommitKeys.filter((item: string) => item !== key);
  }

  private findTargetByRepoKey(repoKey: string): VersionCommitRepositoryTarget | null {
    const target = DEFAULT_VERSION_COMMIT_REPOSITORIES.find(
      (item: VersionCommitRepositoryTarget) => item.key === repoKey
    );
    return target || null;
  }

  private updateCommitByRepo(
    repoKey: string,
    sha: string,
    updater: (commit: VersionCommitRecord) => VersionCommitRecord
  ): void {
    if (repoKey === MANXIA_REPO_KEY && this.manxiaResult) {
      const updatedCommits = this.manxiaResult.commits.map((commit: VersionCommitRecord) => {
        return commit.sha === sha ? updater(commit) : commit;
      });
      this.manxiaResult = this.copyRepositoryResultWithCommits(this.manxiaResult, updatedCommits);
      return;
    }

    if (repoKey === MANXIA_EXT_REPO_KEY && this.manxiaExtensionResult) {
      const updatedCommits = this.manxiaExtensionResult.commits.map((commit: VersionCommitRecord) => {
        return commit.sha === sha ? updater(commit) : commit;
      });
      this.manxiaExtensionResult = this.copyRepositoryResultWithCommits(this.manxiaExtensionResult, updatedCommits);
    }
  }

  private copyRepositoryResultWithCommits(
    source: VersionCommitRepositoryResult,
    commits: VersionCommitRecord[]
  ): VersionCommitRepositoryResult {
    return {
      key: source.key,
      name: source.name,
      apiUrl: source.apiUrl,
      effectiveApiUrl: source.effectiveApiUrl,
      commitsPageUrl: source.commitsPageUrl,
      commits: commits,
      lastFetchedAt: source.lastFetchedAt,
      networkUpdated: source.networkUpdated,
      usingCache: source.usingCache,
      usedProxy: source.usedProxy,
      errorMessage: source.errorMessage
    };
  }

  private applyDetailToCommit(commit: VersionCommitRecord, detail: VersionCommitDetail): VersionCommitRecord {
    return {
      sha: commit.sha,
      shortSha: commit.shortSha,
      message: detail.message || commit.message,
      summary: detail.title || commit.summary,
      title: detail.title || commit.title,
      body: detail.body,
      authorName: detail.authorName || commit.authorName,
      authorLogin: detail.authorLogin || commit.authorLogin,
      date: detail.date || commit.date,
      timestamp: detail.timestamp > 0 ? detail.timestamp : commit.timestamp,
      htmlUrl: detail.htmlUrl || commit.htmlUrl,
      files: detail.files,
      detailLoaded: true,
      detailLoading: false,
      detailError: ''
    };
  }

  private getPageBackgroundResource(): ResourceStr {
    return $r('app.media.bg1');
  }

  private getPageBackgroundTint(): string {
    return this.themeState.currentTheme === ThemeType.DARK
      ? 'rgba(6, 10, 16, 0.24)'
      : 'rgba(244, 248, 252, 0.16)';
  }

  private getPageBackgroundScrimColors(): [ResourceColor, number][] {
    if (this.themeState.currentTheme === ThemeType.DARK) {
      return [
        ['rgba(6, 10, 16, 0.08)', 0.0] as [ResourceColor, number],
        ['rgba(6, 10, 16, 0.18)', 0.52] as [ResourceColor, number],
        ['rgba(6, 10, 16, 0.42)', 1.0] as [ResourceColor, number]
      ];
    }
    return [
      ['rgba(255, 255, 255, 0.02)', 0.0] as [ResourceColor, number],
      ['rgba(244, 248, 252, 0.08)', 0.52] as [ResourceColor, number],
      ['rgba(236, 243, 250, 0.2)', 1.0] as [ResourceColor, number]
    ];
  }

  @Builder
  private buildPageBackground() {
    Stack() {
      Image(this.getPageBackgroundResource())
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.getPageBackgroundTint())
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: this.getPageBackgroundScrimColors()
        })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
  }

  private async loadCommitDetail(repoKey: string, sha: string): Promise<void> {
    const target = this.findTargetByRepoKey(repoKey);
    if (!target) {
      return;
    }

    this.updateCommitByRepo(repoKey, sha, (commit: VersionCommitRecord) => ({
      sha: commit.sha,
      shortSha: commit.shortSha,
      message: commit.message,
      summary: commit.summary,
      title: commit.title,
      body: commit.body,
      authorName: commit.authorName,
      authorLogin: commit.authorLogin,
      date: commit.date,
      timestamp: commit.timestamp,
      htmlUrl: commit.htmlUrl,
      files: commit.files,
      detailLoaded: commit.detailLoaded,
      detailLoading: true,
      detailError: ''
    }));

    try {
      const detail = await this.versionHistoryManager.fetchCommitDetail(target, sha);
      this.updateCommitByRepo(repoKey, sha, (commit: VersionCommitRecord) => this.applyDetailToCommit(commit, detail));
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.updateCommitByRepo(repoKey, sha, (commit: VersionCommitRecord) => ({
        sha: commit.sha,
        shortSha: commit.shortSha,
        message: commit.message,
        summary: commit.summary,
        title: commit.title,
        body: commit.body,
        authorName: commit.authorName,
        authorLogin: commit.authorLogin,
        date: commit.date,
        timestamp: commit.timestamp,
        htmlUrl: commit.htmlUrl,
        files: commit.files,
        detailLoaded: false,
        detailLoading: false,
        detailError: errorMessage
      }));
    }
  }

  private async toggleCommitDetail(repoKey: string, commit: VersionCommitRecord): Promise<void> {
    if (this.isCommitExpanded(repoKey, commit.sha)) {
      this.setCommitExpanded(repoKey, commit.sha, false);
      return;
    }

    this.setCommitExpanded(repoKey, commit.sha, true);
    if (!commit.detailLoaded && !commit.detailLoading) {
      await this.loadCommitDetail(repoKey, commit.sha);
    }
  }

  @Builder
  private buildSummaryCard() {
    Column({ space: 10 }) {
      Row() {
        Column({ space: 4 }) {
          Text('提交记录同步')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          Text(`默认每次拉取最近 ${DEFAULT_VERSION_COMMIT_FETCH_LIMIT} 次提交，旧提交自动缓存`)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button(this.isRefreshing ? '刷新中...' : '刷新')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(Color.White)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .borderRadius(18)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .enabled(!this.isRefreshing)
          .onClick(async () => {
            await this.refreshCommitHistory(false);
          })
      }
      .width('100%')

      if (this.lastRefreshAt > 0) {
        Text(`最近刷新: ${this.formatRefreshTime(this.lastRefreshAt)}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
  }

  @Builder
  private buildFileChangeItem(file: VersionCommitFileChange) {
    Row() {
      Text(file.filename)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(`+${file.additions} / -${file.deletions}`)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(8)
  }

  @Builder
  private buildCommitItem(repoKey: string, commit: VersionCommitRecord) {
    Column({ space: 8 }) {
      Row() {
        Text(commit.summary)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        SymbolGlyph(
          this.isCommitExpanded(repoKey, commit.sha)
            ? $r('sys.symbol.chevron_up')
            : $r('sys.symbol.chevron_down')
        )
          .fontSize(16)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
      }
      .width('100%')
      .onClick(async () => {
        await this.toggleCommitDetail(repoKey, commit);
      })

      Row() {
        Text(commit.shortSha)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))

        Text(` · ${commit.authorName}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(1)
      }
      .width('100%')

      Text(this.formatCommitTime(commit.timestamp))
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')

      if (this.isCommitExpanded(repoKey, commit.sha)) {
        Column({ space: 8 }) {
          if (commit.detailLoading) {
            Row({ space: 8 }) {
              LoadingProgress()
                .width(14)
                .height(14)
                .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

              Text('正在加载提交详情...')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            }
            .width('100%')
          } else {
            Text(`标题：${commit.title || commit.summary}`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .width('100%')

            Text(`内容：${commit.body.length > 0 ? commit.body : '无'}`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .width('100%')

            if (commit.detailError.length > 0) {
              Text(`详情加载失败：${commit.detailError}`)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .width('100%')
            } else {
              Text('修改文件')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .width('100%')

              if (commit.files.length === 0) {
                Text('暂无文件变更信息')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .width('100%')
              } else {
                ForEach(commit.files, (file: VersionCommitFileChange) => {
                  this.buildFileChangeItem(file)
                }, (file: VersionCommitFileChange) => `${file.filename}_${file.status}_${file.changes}`)
              }
            }

            Button('浏览器查看该提交')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(Color.White)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .borderRadius(10)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .onClick(async () => {
                await this.openExternalUrl(commit.htmlUrl);
              })
          }
        }
        .width('100%')
        .padding(10)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
        .borderRadius(10)
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(12)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
  }

  @Builder
  private buildRepositoryCard(
    repoKey: string,
    displayName: string,
    result: VersionCommitRepositoryResult | null,
    showCachedHistory: boolean,
    toggleHistory: () => void
  ) {
    Column({ space: 12 }) {
      Row() {
        Text(displayName)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)

        if (result && result.commitsPageUrl.length > 0) {
          Button('GitHub')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(14)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .onClick(async () => {
              await this.openExternalUrl(result.commitsPageUrl);
            })
        }
      }
      .width('100%')

      if (!result) {
        Text('正在加载提交记录...')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
      } else {
        Text(this.getCommitStatusText(result))
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')

        Text(`仓库更新时间: ${this.formatRefreshTime(result.lastFetchedAt)}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .width('100%')

        if (result.errorMessage.length > 0) {
          Text(`提示: ${result.errorMessage}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        if (result.commits.length === 0) {
          Column({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(24)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])

            Text('暂无可展示的提交记录')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          ForEach(this.getVisibleCommits(result, showCachedHistory), (commit: VersionCommitRecord) => {
            this.buildCommitItem(repoKey, commit)
          }, (commit: VersionCommitRecord) => commit.sha)

          if (result.commits.length > DEFAULT_VERSION_COMMIT_FETCH_LIMIT) {
            Button(showCachedHistory ? '收起历史缓存' : `查看历史缓存 (${result.commits.length - DEFAULT_VERSION_COMMIT_FETCH_LIMIT})`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .backgroundColor(Color.Transparent)
              .borderRadius(10)
              .padding({ left: 8, right: 8, top: 6, bottom: 6 })
              .onClick(() => {
                toggleHistory();
              })
          }
        }
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
  }

  build() {
    HdsNavDestination() {
      Stack() {
        this.buildPageBackground()

        if (this.isLoading) {
          Column({ space: 14 }) {
            LoadingProgress()
              .width(32)
              .height(32)
              .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

            Text('正在同步版本记录...')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          Scroll(this.scroller) {
            Column({ space: 12 }) {
              Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))

              this.buildSummaryCard()

              this.buildRepositoryCard(
                MANXIA_REPO_KEY,
                '漫匣仓库',
                this.manxiaResult,
                this.showManxiaCachedHistory,
                () => {
                  this.showManxiaCachedHistory = !this.showManxiaCachedHistory;
                }
              )

              this.buildRepositoryCard(
                MANXIA_EXT_REPO_KEY,
                '漫匣图源仓库',
                this.manxiaExtensionResult,
                this.showExtensionCachedHistory,
                () => {
                  this.showExtensionCachedHistory = !this.showExtensionCachedHistory;
                }
              )

              Blank().height(24 + this.navigationBarHeight)
            }
            .width('100%')
            .constraintSize({ maxWidth: this.responsive_maxContentWidth })
            .padding({ top: 8 })
          }
          .width('100%')
          .height('100%')
          .align(Alignment.TopStart)
          .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding })
          .edgeEffect(EdgeEffect.Spring)
          .scrollBar(BarState.Auto)
        }
        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '版本记录',
          appFontFamily: this.appFontFamily,
          contentPadding: this.responsive_contentPadding,
          maxContentWidth: this.responsive_maxContentWidth,
          pathStack: this.pathStack
        })
      }
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.onPageShow();
      this.onReady();
    })
    .backgroundColor(Color.Transparent)
  }
}

export { VersionHistoryPage }
