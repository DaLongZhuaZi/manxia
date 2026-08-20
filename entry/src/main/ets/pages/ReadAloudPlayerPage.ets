import { promptAction, LengthMetrics } from '@kit.ArkUI';
import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { common } from '@kit.AbilityKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { continuationStateHelper } from '../Framework/Distributed/ContinuationStateHelper';
import { ReadAloudController } from '../Framework/ReadAloud/ReadAloudController';
import { eventBus, GameEvent, IEventPayload } from '../Framework/EventBus';
import { ReadAloudPlaybackState, ReadAloudSessionContext, ReadAloudStateSnapshot } from '../Framework/ReadAloud/ReadAloudTypes';
import { WindowManager, DisplayMode } from '../Utils/WindowManager';
import { PageWindowCoordinator } from '../Utils/PageWindowCoordinator';
import { ThemeAwareHelper, ThemeAwareState } from '../Framework/Components/ThemeAware';
import { SourceDialogScaffold } from '../Framework/Components/SourceDialogScaffold';
import { DialogSurfaceStyleHelper } from '../Framework/Components/DialogSurfaceStyleHelper';
import {
  NovelAudioReadAloudLaunchParams,
  NovelAudioReadAloudSnapshot,
  NovelAudioReadAloudStateListener,
  getNovelAudioReadAloudSessionManager
} from '../Framework/ReadAloud/NovelAudioReadAloudSessionManager';
import { NovelReaderPageParams } from './NovelBookshelfPage';
import { ReadAloudPlayerAbilityParams } from '../Framework/ReadAloud/ReadAloudPlayerAbilityParamStore';
import { READ_ALOUD_PLAYER_ABILITY_HOST_SINGLETON } from 'manxia_novel/src/main/ets/Framework/ReadAloud/ReadAloudPlayerAbilityConstants';

const TAG = 'ReadAloudPlayerPage';
const PLAYER_SKIP_CHARS: number = 420;
const PLAYER_TOP_CONTENT_PADDING: number = 8;
const PLAYER_DISPLAY_RESTORE_DELAY_MS: number = 140;
const READ_ALOUD_UI_STATUS_TEXT_KEY = 'ReadAloudUiStatusText';
const READ_ALOUD_UI_STATUS_DETAIL_KEY = 'ReadAloudUiStatusDetail';
const READ_ALOUD_FLOATING_BALL_SUPPRESSED_KEY = 'ReadAloudFloatingBallSuppressed';
const READ_ALOUD_REMOTE_CURRENT_SEGMENT_INDEX_KEY = 'ReadAloudRemoteCurrentSegmentIndex';
const READ_ALOUD_REMOTE_TOTAL_SEGMENTS_KEY = 'ReadAloudRemoteTotalSegments';
const READ_ALOUD_REMOTE_CACHED_SEGMENTS_KEY = 'ReadAloudRemoteCachedSegments';
const READ_ALOUD_REMOTE_CACHED_BYTES_KEY = 'ReadAloudRemoteCachedBytes';

@Component
export struct ReadAloudPlayerPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  @State hasSession: boolean = false;
  @State isPlaying: boolean = false;
  @State bookTitle: string = '听书播放器';
  @State chapterTitle: string = '';
  @State coverUrl: string = '';
  @State progressPercent: number = 0;
  @State progressSliderValue: number = 0;
  @State progressText: string = '0%';
  @State progressDragPreviewText: string = '';
  @State isProgressDragging: boolean = false;
  @State isInfoPanelCollapsed: boolean = false;
  @State activeButtonKey: string = '';
  @State statusText: string = '未播放';
  @State chapterInfoText: string = '--';
  @State pageInfoText: string = '--';
  @State charInfoText: string = '--';
  @State chunkInfoText: string = '--';
  @State engineInfoText: string = '--';
  @State speedInfoText: string = '--';
  @State excerptText: string = '';
  @State remoteSegmentText: string = '--';
  @State remoteCacheSegmentText: string = '--';
  @State remoteCacheBytesText: string = '--';
  @State sleepTimerText: string = '未设置';
  @State sleepTimerActive: boolean = false;
  @State showSleepTimerDialog: boolean = false;
  @State sleepTimerDialogOpacity: number = 0;
  @State sleepTimerDialogScale: number = 0.96;
  @State customSleepTimerValue: string = '45';
  @State customSleepTimerUnit: 'minute' | 'hour' = 'minute';
  @State entered: boolean = false;
  @State isNovelAudioMode: boolean = false;

  // 主题状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private componentId: string = `ReadAloudPlayerPage_${Date.now()}`;

  private readAloudController: ReadAloudController = ReadAloudController.getInstance();
  private novelAudioSessionManager = getNovelAudioReadAloudSessionManager();
  private previousDisplayMode: DisplayMode = DisplayMode.DEFAULT;
  private returnHostPage: string = '';
  private playerHostMode: string = '';
  private hasCapturedRouteState: boolean = false;
  private displayRestoreTimer: number = -1;
  private sleepTimerRefreshTimer: number = -1;
  private uiContext: UIContext | null = null;
  private pendingSeekPercent: number = -1;
  private isApplyingProgressSeek: boolean = false;
  private progressPreviewHintToken: number = 0;

  private onReadAloudStateChanged: (payload: IEventPayload) => void = (_payload: IEventPayload): void => {
    this.refreshPlayerState();
  };
  private onReadAloudCacheUpdated: (_payload: IEventPayload) => void = (_payload: IEventPayload): void => {
    this.refreshPlayerState();
  };
  private onNovelAudioSessionChanged: NovelAudioReadAloudStateListener = (_snapshot: NovelAudioReadAloudSnapshot): void => {
    this.refreshPlayerState();
  };

  /**
   * [修复] 应用当前 mission 的接续状态（ACTIVE=显示系统接续入口）
   */
  private applyMissionContinueState(active: boolean): void {
    try {
      const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!hostContext) {
        return;
      }
      continuationStateHelper.setMissionContinueState(hostContext, active);
    } catch (error) {
      logger.warn(TAG, `设置接续状态失败: ${String(error)}`);
    }
  }

  /**
   * [修复] 激活接续入口（页面检查点）：
   * 入口按场景无条件显示；权限在触发接续时校验，此处异步确保权限就绪
   */
  private applyMissionContinueStateWithPermission(): void {
    try {
      const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!hostContext) {
        return;
      }
      continuationStateHelper.activateMissionContinueEntry(hostContext);
    } catch (error) {
      logger.warn(TAG, `设置接续状态失败: ${String(error)}`);
    }
  }

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, () => {});
    // [修复] 权限前置激活系统接续入口（权限未授权时不进入接续状态）
    this.applyMissionContinueStateWithPermission();
    this.captureRouteState('aboutToAppear');
    this.applyPreferredDisplayMode('aboutToAppear');
    AppStorage.setOrCreate('ReadAloudCurrentHostPage', 'ReadAloudPlayerPage');
    AppStorage.setOrCreate(READ_ALOUD_FLOATING_BALL_SUPPRESSED_KEY, true);
    eventBus.subscribe(GameEvent.READ_ALOUD_STATE_CHANGED, this.onReadAloudStateChanged);
    eventBus.subscribe(GameEvent.READ_ALOUD_CACHE_UPDATED, this.onReadAloudCacheUpdated);
    this.novelAudioSessionManager.subscribe(this.onNovelAudioSessionChanged);
    this.startSleepTimerRefreshTimer();
    this.refreshPlayerState();
    if (!this.novelAudioSessionManager.hasActiveSession()) {
      this.readAloudController.refreshMediaSession();
    }
  }

  aboutToDisappear(): void {
    this.clearDisplayRestoreTimer();
    // [修复] 听书退出时关闭系统接续入口
    this.applyMissionContinueState(false);
    this.stopSleepTimerRefreshTimer();
    this.restorePreviousDisplayMode('aboutToDisappear');
    const currentHostPage = (AppStorage.get<string>('ReadAloudCurrentHostPage') ?? '').trim();
    if (this.returnHostPage.length > 0) {
      AppStorage.setOrCreate('ReadAloudCurrentHostPage', this.returnHostPage);
    } else if (currentHostPage === 'ReadAloudPlayerPage') {
      AppStorage.setOrCreate('ReadAloudCurrentHostPage', '');
    }
    AppStorage.setOrCreate(READ_ALOUD_FLOATING_BALL_SUPPRESSED_KEY, false);
    this.clearPlayerReturnMarkers();
    eventBus.unsubscribe(GameEvent.READ_ALOUD_STATE_CHANGED, this.onReadAloudStateChanged);
    eventBus.unsubscribe(GameEvent.READ_ALOUD_CACHE_UPDATED, this.onReadAloudCacheUpdated);
    this.novelAudioSessionManager.unsubscribe(this.onNovelAudioSessionChanged);
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
  }

  onPageShow(): void {
    // [修复] 听书页面重新显示时按权限条件保持接续入口
    this.applyMissionContinueStateWithPermission();
    this.applyPreferredDisplayMode('onPageShow');
    this.scheduleDisplayRestore('onPageShow');
    AppStorage.setOrCreate('ReadAloudCurrentHostPage', 'ReadAloudPlayerPage');
    AppStorage.setOrCreate(READ_ALOUD_FLOATING_BALL_SUPPRESSED_KEY, true);
    this.refreshPlayerState();
  }

  onPageHide(): void {
    this.clearDisplayRestoreTimer();
    const isInBackground = this.isAppInBackground();
    if (this.isNovelAudioMode) {
      this.novelAudioSessionManager.handlePageHide(isInBackground);
      return;
    }
    if (isInBackground) {
      this.readAloudController.handlePageHide();
    }
  }

  private isAppInBackground(): boolean {
    const backgroundFlag = AppStorage.get<boolean>('isInBackground');
    return backgroundFlag === true;
  }

  private ensureUiContext(): UIContext | null {
    if (!this.uiContext) {
      this.uiContext = this.getUIContext();
    }
    return this.uiContext;
  }

  private resolveStoredDisplayMode(): DisplayMode {
    if (this.playerHostMode === READ_ALOUD_PLAYER_ABILITY_HOST_SINGLETON) {
      return this.previousDisplayMode;
    }
    const storedMode = (AppStorage.get<string>('ReadAloudPlayerReturnDisplayMode') ?? '').trim();
    switch (storedMode) {
      case DisplayMode.DEFAULT:
      case DisplayMode.FULL_IMMERSIVE:
      case DisplayMode.HIDE_STATUS_BAR:
      case DisplayMode.HIDE_NAVIGATION_BAR:
      case DisplayMode.IMMERSIVE_WITH_BARS:
      case DisplayMode.STATUS_SAFE_BOTTOM_IMMERSIVE:
        return storedMode as DisplayMode;
      default:
        return WindowManager.getCurrentMode();
    }
  }

  private captureRouteState(trigger: string): void {
    if (this.hasCapturedRouteState) {
      return;
    }
    this.ensureUiContext();
    if (this.playerHostMode !== READ_ALOUD_PLAYER_ABILITY_HOST_SINGLETON) {
      this.previousDisplayMode = this.resolveStoredDisplayMode();
      this.returnHostPage = (AppStorage.get<string>('ReadAloudPlayerReturnHostPage') ?? '').trim();
    }
    this.hasCapturedRouteState = true;
    logger.info(
      TAG,
      `捕获听书独立页返回上下文: 触发源=${trigger}, 上一显示模式=${this.previousDisplayMode}, 返回页面=${this.returnHostPage || '无'}`
    );
  }

  private shouldUseImmersiveMode(): boolean {
    return this.previousDisplayMode !== DisplayMode.DEFAULT;
  }

  private applyPreferredDisplayMode(trigger: string): void {
    const context = this.ensureUiContext();
    if (!context) {
      logger.warn(TAG, `应用听书页显示模式失败: 触发源=${trigger}, 界面上下文为空`);
      return;
    }
    const targetMode = this.previousDisplayMode;
    const currentMode = WindowManager.getCurrentMode();
    if (currentMode === targetMode) {
      logger.debug(TAG, `听书独立页显示模式无需切换: 触发源=${trigger}, 模式=${targetMode}`);
      return;
    }
    PageWindowCoordinator.applyPagePolicy('ReadAloudPlayerPage', context, this.previousDisplayMode);
    logger.info(TAG, `应用听书独立页显示模式: 触发源=${trigger}, 模式=${targetMode}`);
  }

  private restorePreviousDisplayMode(trigger: string): void {
    const context = this.ensureUiContext();
    if (!context) {
      logger.warn(TAG, `恢复听书页来源显示模式失败: 触发源=${trigger}, 界面上下文为空`);
      return;
    }
    const currentMode = WindowManager.getCurrentMode();
    if (currentMode === this.previousDisplayMode) {
      logger.debug(TAG, `听书页来源显示模式无需恢复: 触发源=${trigger}, 模式=${this.previousDisplayMode}`);
      return;
    }
    PageWindowCoordinator.restoreDisplayMode(this.previousDisplayMode, context);
    logger.info(TAG, `恢复听书页来源显示模式: 触发源=${trigger}, 模式=${this.previousDisplayMode}`);
  }

  private clearDisplayRestoreTimer(): void {
    if (this.displayRestoreTimer >= 0) {
      clearTimeout(this.displayRestoreTimer);
      this.displayRestoreTimer = -1;
    }
  }

  private startSleepTimerRefreshTimer(): void {
    this.stopSleepTimerRefreshTimer();
    this.sleepTimerRefreshTimer = setInterval(() => {
      this.refreshSleepTimerState();
      this.refreshPlayerState();
    }, 1000) as number;
  }

  private stopSleepTimerRefreshTimer(): void {
    if (this.sleepTimerRefreshTimer >= 0) {
      clearInterval(this.sleepTimerRefreshTimer);
      this.sleepTimerRefreshTimer = -1;
    }
  }

  private scheduleDisplayRestore(trigger: string, delayMs: number = PLAYER_DISPLAY_RESTORE_DELAY_MS): void {
    if (!this.shouldUseImmersiveMode()) {
      return;
    }
    this.clearDisplayRestoreTimer();
    this.displayRestoreTimer = setTimeout(() => {
      this.displayRestoreTimer = -1;
      this.applyPreferredDisplayMode(`delayed_${trigger}`);
    }, delayMs);
  }

  private forceReaderImmersiveBeforeExit(trigger: string): void {
    const context = this.ensureUiContext();
    if (!context) {
      logger.warn(TAG, `返回阅读器前恢复沉浸失败: 触发源=${trigger}, 界面上下文为空`);
      return;
    }
    this.previousDisplayMode = DisplayMode.FULL_IMMERSIVE;
    WindowManager.setDisplayMode(DisplayMode.FULL_IMMERSIVE, context);
    setTimeout(() => {
      WindowManager.setDisplayMode(DisplayMode.FULL_IMMERSIVE, context);
    }, 80);
    setTimeout(() => {
      WindowManager.setDisplayMode(DisplayMode.FULL_IMMERSIVE, context);
    }, 180);
    logger.info(TAG, `返回阅读器前强制恢复沉浸: 触发源=${trigger}`);
  }

  private clearPlayerReturnMarkers(): void {
    AppStorage.setOrCreate('ReadAloudPlayerOpeningAt', 0);
    AppStorage.setOrCreate('ReadAloudPlayerReturnHostPage', '');
    AppStorage.setOrCreate('ReadAloudPlayerReturnDisplayMode', '');
  }

  private refreshSleepTimerState(): void {
    const snapshot = this.readAloudController.getSleepTimerSnapshot();
    this.sleepTimerActive = snapshot.active;
    this.sleepTimerText = snapshot.active
      ? `剩余 ${this.formatDuration(snapshot.remainingMs)}`
      : '未设置';
  }

  private refreshRemoteStatus(snapshot: ReadAloudStateSnapshot): void {
    if (this.isNovelAudioMode) {
      this.remoteSegmentText = '--';
      this.remoteCacheSegmentText = '--';
      this.remoteCacheBytesText = '--';
      return;
    }
    if (String(snapshot.settings.engineType ?? 'SYSTEM') !== 'REMOTE') {
      this.remoteSegmentText = '--';
      this.remoteCacheSegmentText = '--';
      this.remoteCacheBytesText = '--';
      return;
    }
    const currentSegment = AppStorage.get<number>(READ_ALOUD_REMOTE_CURRENT_SEGMENT_INDEX_KEY) ?? 0;
    const totalSegments = AppStorage.get<number>(READ_ALOUD_REMOTE_TOTAL_SEGMENTS_KEY) ?? 0;
    const cachedSegments = AppStorage.get<number>(READ_ALOUD_REMOTE_CACHED_SEGMENTS_KEY) ?? 0;
    const cachedBytes = AppStorage.get<number>(READ_ALOUD_REMOTE_CACHED_BYTES_KEY) ?? 0;
    this.remoteSegmentText = totalSegments > 0 ? `${currentSegment}/${totalSegments}` : '--';
    this.remoteCacheSegmentText = totalSegments > 0
      ? `${Math.min(cachedSegments, totalSegments)}/${totalSegments}`
      : `${cachedSegments}`;
    this.remoteCacheBytesText = this.formatBytes(cachedBytes);
  }

  private formatBytes(bytes: number): string {
    const safeBytes = Math.max(0, Math.floor(bytes));
    if (safeBytes >= 1024 * 1024) {
      return `${(safeBytes / (1024 * 1024)).toFixed(2)} MB`;
    }
    if (safeBytes >= 1024) {
      return `${(safeBytes / 1024).toFixed(1)} KB`;
    }
    return `${safeBytes} B`;
  }

  private formatDuration(durationMs: number): string {
    const totalSeconds = Math.max(0, Math.floor(durationMs / 1000));
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;
    if (hours > 0) {
      return `${hours}小时${minutes}分钟`;
    }
    if (minutes > 0) {
      return `${minutes}分钟${seconds}秒`;
    }
    return `${seconds}秒`;
  }

  private resolveButtonScale(buttonKey: string): number {
    return this.activeButtonKey === buttonKey ? 0.94 : 1;
  }

  private runAnimatedButtonAction(buttonKey: string, action: () => void): void {
    this.getUIContext().animateTo({ duration: 90, curve: Curve.EaseOut }, () => {
      this.activeButtonKey = buttonKey;
    });
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: 150, curve: Curve.EaseOut }, () => {
        if (this.activeButtonKey === buttonKey) {
          this.activeButtonKey = '';
        }
      });
    }, 90);
    action();
  }

  private resolveSeekDurationMsForTextMode(snapshot: ReadAloudStateSnapshot, context: ReadAloudSessionContext | null): number {
    if (snapshot.totalDurationMs > 0) {
      return Math.max(1, Math.floor(snapshot.totalDurationMs));
    }
    if (!context || !context.content || context.content.length <= 0) {
      return -1;
    }
    const speed = Math.max(0.5, snapshot.settings.speed ?? 1);
    const estimatedMs = Math.floor((context.content.length / Math.max(1, 11 * speed)) * 1000);
    return Math.max(1, estimatedMs);
  }

  private resolveSeekDurationMsForCurrentMode(): number {
    if (this.isNovelAudioMode) {
      const audioSnapshot = this.novelAudioSessionManager.getSnapshot();
      if (audioSnapshot.audioDurationMs > 0) {
        return Math.max(1, Math.floor(audioSnapshot.audioDurationMs));
      }
      return -1;
    }
    const snapshot = this.readAloudController.getSnapshot();
    const context = this.readAloudController.getContextSnapshot();
    return this.resolveSeekDurationMsForTextMode(snapshot, context);
  }

  private updateProgressSliderValueFromState(): void {
    if (this.isProgressDragging || this.isApplyingProgressSeek || this.pendingSeekPercent >= 0) {
      return;
    }
    this.progressSliderValue = Math.max(0, Math.min(100, this.progressPercent));
  }

  private updateProgressDragPreviewText(percent: number): void {
    const safePercent = Math.max(0, Math.min(100, percent));
    const durationMs = this.resolveSeekDurationMsForCurrentMode();
    if (durationMs > 0) {
      const targetMs = Math.floor((safePercent / 100) * durationMs);
      this.progressDragPreviewText = `定位预览：${this.formatDuration(targetMs)} / ${this.formatDuration(durationMs)}`;
      return;
    }
    this.progressDragPreviewText = `定位预览：${Math.round(safePercent)}%`;
  }

  private onProgressSliderChange(value: number, mode: SliderChangeMode): void {
    const safeValue = Math.max(0, Math.min(100, value));
    this.progressSliderValue = safeValue;
    this.updateProgressDragPreviewText(safeValue);
    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
      this.isProgressDragging = true;
      return;
    }
    this.isProgressDragging = false;
    if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
      this.enqueueProgressSeek(safeValue);
    }
  }

  private enqueueProgressSeek(percent: number): void {
    const safePercent = Math.max(0, Math.min(100, percent));
    this.pendingSeekPercent = safePercent;
    if (this.isApplyingProgressSeek) {
      return;
    }
    this.isApplyingProgressSeek = true;
    void this.flushQueuedProgressSeek();
  }

  private async flushQueuedProgressSeek(): Promise<void> {
    try {
      while (this.pendingSeekPercent >= 0) {
        const targetPercent = this.pendingSeekPercent;
        this.pendingSeekPercent = -1;
        await this.commitProgressSeekFromSlider(targetPercent);
      }
    } finally {
      this.isApplyingProgressSeek = false;
      this.updateProgressSliderValueFromState();
      this.scheduleProgressPreviewClear(900);
    }
  }

  private scheduleProgressPreviewClear(delayMs: number): void {
    const clearToken = this.progressPreviewHintToken + 1;
    this.progressPreviewHintToken = clearToken;
    setTimeout(() => {
      if (this.progressPreviewHintToken !== clearToken) {
        return;
      }
      if (this.isProgressDragging || this.isApplyingProgressSeek || this.pendingSeekPercent >= 0) {
        return;
      }
      this.progressDragPreviewText = '';
    }, delayMs);
  }

  private resetProgressSeekState(): void {
    this.pendingSeekPercent = -1;
    this.isApplyingProgressSeek = false;
    this.progressPreviewHintToken += 1;
  }

  private getProgressHintText(): string {
    if (this.isProgressDragging) {
      return this.progressDragPreviewText.length > 0 ? this.progressDragPreviewText : '松手后会定位到目标进度';
    }
    if (this.isApplyingProgressSeek || this.pendingSeekPercent >= 0) {
      return this.progressDragPreviewText.length > 0 ? this.progressDragPreviewText : '正在定位到目标进度...';
    }
    return '拖动或点击进度条可快速定位，播放不中断';
  }

  private async commitProgressSeekFromSlider(percent: number): Promise<void> {
    if (!this.hasSession) {
      this.progressDragPreviewText = '';
      return;
    }
    const safePercent = Math.max(0, Math.min(100, percent));
    if (this.isNovelAudioMode) {
      const snapshot = this.novelAudioSessionManager.getSnapshot();
      const durationMs = Math.max(0, Math.floor(snapshot.audioDurationMs));
      if (durationMs <= 0) {
        this.getUIContext().getPromptAction().showToast({ message: '当前音频时长未就绪，暂无法定位', duration: 1400 });
        this.progressDragPreviewText = '';
        return;
      }
      const targetMs = Math.floor((safePercent / 100) * durationMs);
      const success = await this.novelAudioSessionManager.seekToPosition(targetMs, 'player_progress_slider');
      if (!success) {
        this.getUIContext().getPromptAction().showToast({ message: '拖动定位失败，请稍后重试', duration: 1400 });
      }
      this.refreshPlayerState();
      this.progressDragPreviewText = `已定位：${this.formatDuration(targetMs)} / ${this.formatDuration(durationMs)}`;
      this.scheduleProgressPreviewClear(900);
      return;
    }

    const snapshot = this.readAloudController.getSnapshot();
    const context = this.readAloudController.getContextSnapshot();
    const durationMs = this.resolveSeekDurationMsForTextMode(snapshot, context);
    if (durationMs <= 0) {
      this.progressDragPreviewText = '';
      return;
    }
    const targetMs = Math.floor((safePercent / 100) * durationMs);
    this.readAloudController.seekToPositionMs(targetMs, 'player_progress_slider');
    this.readAloudController.refreshMediaSession();
    this.refreshPlayerState();
    this.progressDragPreviewText = `已定位：${Math.round(safePercent)}%`;
    this.scheduleProgressPreviewClear(900);
  }

  private toggleInfoPanelCollapsed(): void {
    this.getUIContext().animateTo({ duration: 260, curve: Curve.EaseInOut }, () => {
      this.isInfoPanelCollapsed = !this.isInfoPanelCollapsed;
    });
  }

  private resolveCoverSource(raw: string): ResourceStr {
    if (!raw || raw.length <= 0) {
      return '';
    }
    if (raw.startsWith('http://') || raw.startsWith('https://') || raw.startsWith('file://')) {
      return raw;
    }
    if (raw.startsWith('app.media.')) {
      const resourceName = raw.substring('app.media.'.length);
      if (resourceName === 'mangabook') {
        return $r('app.media.mangabook');
      }
      if (resourceName === 'ic_ebook') {
        return $r('app.media.ic_ebook');
      }
      if (resourceName === 'icon') {
        return $r('app.media.icon');
      }
      return $r('app.media.ic_ebook');
    }
    if (raw.startsWith('/')) {
      return `file://${raw}`;
    }
    return raw;
  }

  private isRemoteEngineActive(): boolean {
    if (this.isNovelAudioMode) {
      return false;
    }
    return this.engineInfoText === '远程 TTS';
  }

  private showSleepTimerDialogWithAnimation(): void {
    this.showSleepTimerDialog = true;
    this.sleepTimerDialogOpacity = 0;
    this.sleepTimerDialogScale = 0.96;
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
        this.sleepTimerDialogOpacity = 1;
        this.sleepTimerDialogScale = 1;
      });
    }, 0);
  }

  private hideSleepTimerDialogWithAnimation(): void {
    if (!this.showSleepTimerDialog) {
      return;
    }
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseIn }, () => {
      this.sleepTimerDialogOpacity = 0;
      this.sleepTimerDialogScale = 0.96;
    });
    setTimeout(() => {
      this.showSleepTimerDialog = false;
    }, 180);
  }

  private applySleepTimer(durationMs: number): void {
    this.readAloudController.scheduleSleepTimer(durationMs);
    this.refreshSleepTimerState();
    this.getUIContext().getPromptAction().showToast({
      message: `已设置定时关闭：${this.formatDuration(durationMs)}`,
      duration: 1500
    });
    this.hideSleepTimerDialogWithAnimation();
  }

  private cancelSleepTimer(): void {
    this.readAloudController.cancelSleepTimer();
    this.refreshSleepTimerState();
    this.getUIContext().getPromptAction().showToast({
      message: '已取消定时关闭',
      duration: 1500
    });
  }

  private applyCustomSleepTimer(): void {
    const parsedValue = Number.parseInt(this.customSleepTimerValue.trim(), 10);
    if (!Number.isFinite(parsedValue) || parsedValue <= 0) {
      this.getUIContext().getPromptAction().showToast({
        message: '请输入大于 0 的定时时长',
        duration: 1600
      });
      return;
    }
    const durationMs = this.customSleepTimerUnit === 'hour'
      ? parsedValue * 60 * 60 * 1000
      : parsedValue * 60 * 1000;
    this.applySleepTimer(durationMs);
  }

  private resolveNovelAudioLaunchParams(param: NovelReaderPageParams | null): NovelAudioReadAloudLaunchParams | null {
    if (!param) {
      return null;
    }
    if (!param.sourceId || !param.bookUrl) {
      return null;
    }
    return {
      sourceId: param.sourceId,
      bookUrl: param.bookUrl,
      bookName: param.bookName,
      chapterUrl: param.chapterUrl,
      chapterTitle: param.chapterTitle,
      chapterIndex: Math.max(0, param.chapterIndex),
      totalChapters: Math.max(0, param.totalChapters),
      tocUrl: param.tocUrl || param.bookUrl,
      author: param.author || '',
      coverUrl: param.coverUrl || '',
      autoStartReadAloud: param.autoStartReadAloud === true,
      readerOpenFlowId: param.readerOpenFlowId
    };
  }

  private async initializeNovelAudioSessionIfNeeded(param: NovelReaderPageParams | null): Promise<void> {
    const launchParams = this.resolveNovelAudioLaunchParams(param);
    if (!launchParams) {
      this.isNovelAudioMode = this.novelAudioSessionManager.hasActiveSession();
      this.refreshPlayerState();
      return;
    }

    const hasActiveSession = this.novelAudioSessionManager.hasActiveSession();
    const shouldAutoStart = launchParams.autoStartReadAloud === true || !hasActiveSession;
    const finalLaunchParams: NovelAudioReadAloudLaunchParams = {
      sourceId: launchParams.sourceId,
      bookUrl: launchParams.bookUrl,
      bookName: launchParams.bookName,
      chapterUrl: launchParams.chapterUrl,
      chapterTitle: launchParams.chapterTitle,
      chapterIndex: launchParams.chapterIndex,
      totalChapters: launchParams.totalChapters,
      tocUrl: launchParams.tocUrl,
      author: launchParams.author,
      coverUrl: launchParams.coverUrl,
      autoStartReadAloud: shouldAutoStart,
      readerOpenFlowId: launchParams.readerOpenFlowId
    };

    logger.info(
      TAG,
      `初始化听书小说会话: 图源=${finalLaunchParams.sourceId}, 章节索引=${finalLaunchParams.chapterIndex}, 自动播放=${finalLaunchParams.autoStartReadAloud === true}, 章节地址=${(finalLaunchParams.chapterUrl || '').substring(0, 160)}`
    );

    // 听书小说改为 AVPlayer 独立链路，避免与 ReadAloudController 会话互相影响
    this.readAloudController.release();
    const started = await this.novelAudioSessionManager.startSession(finalLaunchParams);
    if (started) {
      this.isNovelAudioMode = true;
      logger.info(TAG, `听书播放器页会话已激活: 图源=${finalLaunchParams.sourceId}, 章节索引=${finalLaunchParams.chapterIndex}`);
    } else {
      this.isNovelAudioMode = this.novelAudioSessionManager.hasActiveSession();
      logger.warn(TAG, `听书播放器页会话初始化返回false: 图源=${finalLaunchParams.sourceId}, 章节索引=${finalLaunchParams.chapterIndex}`);
    }
    this.refreshPlayerState();
  }

  private applyNovelAudioSnapshot(snapshot: NovelAudioReadAloudSnapshot): void {
    const hasSession = snapshot.hasSession;
    this.hasSession = hasSession;
    this.isPlaying = snapshot.isPlaying;
    this.statusText = snapshot.isLoading
      ? '正在准备音频...'
      : snapshot.isPlaying
        ? '播放中'
        : (snapshot.loadErrorMessage.length > 0 ? '播放异常' : '已暂停');
    if (!hasSession) {
      this.bookTitle = '听书播放器';
      this.chapterTitle = '当前没有可播放内容';
      this.coverUrl = '';
      this.progressPercent = 0;
      this.progressText = '0%';
      this.resetProgressSeekState();
      this.isProgressDragging = false;
      this.progressDragPreviewText = '';
      this.progressSliderValue = 0;
      this.chapterInfoText = '--';
      this.pageInfoText = '--';
      this.charInfoText = '--';
      this.chunkInfoText = '--';
      this.engineInfoText = '--';
      this.speedInfoText = '--';
      this.excerptText = '';
      this.remoteSegmentText = '--';
      this.remoteCacheSegmentText = '--';
      this.remoteCacheBytesText = '--';
      this.refreshSleepTimerState();
      return;
    }

    this.bookTitle = snapshot.bookName.length > 0 ? snapshot.bookName : '听书播放器';
    this.chapterTitle = snapshot.chapterTitle.length > 0
      ? snapshot.chapterTitle
      : `第${snapshot.chapterIndex + 1}章`;
    this.coverUrl = snapshot.coverUrl;
    const durationMs = Math.max(0, snapshot.audioDurationMs);
    const positionMs = Math.max(0, Math.min(snapshot.audioPositionMs, durationMs > 0 ? durationMs : snapshot.audioPositionMs));
    this.progressPercent = durationMs > 0 ? Math.max(0, Math.min(100, (positionMs / durationMs) * 100)) : 0;
    this.progressText = durationMs > 0
      ? `${this.formatDuration(positionMs)} / ${this.formatDuration(durationMs)}`
      : '0%';
    this.updateProgressSliderValueFromState();
    this.chapterInfoText = snapshot.totalChapters > 0
      ? `${snapshot.chapterIndex + 1}/${snapshot.totalChapters}`
      : `第${snapshot.chapterIndex + 1}章`;
    this.pageInfoText = '--';
    this.charInfoText = '--';
    this.chunkInfoText = snapshot.audioChapterCached ? '已缓存' : '未缓存';
    this.engineInfoText = '书源音频';
    this.speedInfoText = snapshot.isCachingCurrentChapterAudio ? '缓存中' : '直连';
    this.excerptText = snapshot.loadErrorMessage.length > 0
      ? snapshot.loadErrorMessage
      : (snapshot.audioSourceUrl.length > 0 ? snapshot.audioSourceUrl : '已就绪，点击播放开始听书');
    this.remoteSegmentText = '--';
    this.remoteCacheSegmentText = '--';
    this.remoteCacheBytesText = '--';
    this.refreshSleepTimerState();
  }

  private refreshPlayerState(): void {
    const audioSnapshot = this.novelAudioSessionManager.getSnapshot();
    if (audioSnapshot.hasSession) {
      this.isNovelAudioMode = true;
      this.applyNovelAudioSnapshot(audioSnapshot);
      return;
    }
    if (this.isNovelAudioMode) {
      this.isNovelAudioMode = false;
    }

    const snapshot = this.readAloudController.getSnapshot();
    const context = this.readAloudController.getContextSnapshot();
    const hasValidContext = context !== null && snapshot.hasContext;
    this.hasSession = hasValidContext;
    this.isPlaying = snapshot.playbackState === ReadAloudPlaybackState.PLAYING;
    this.statusText = this.getDetailedStatusText(snapshot.playbackState);

    if (!context || !hasValidContext) {
      this.bookTitle = '听书播放器';
      this.chapterTitle = '当前没有可播放内容';
      this.coverUrl = '';
      this.progressPercent = 0;
      this.progressText = '0%';
      this.resetProgressSeekState();
      this.isProgressDragging = false;
      this.progressDragPreviewText = '';
      this.progressSliderValue = 0;
      this.chapterInfoText = '--';
      this.pageInfoText = '--';
      this.charInfoText = '--';
      this.chunkInfoText = '--';
      this.engineInfoText = '--';
      this.speedInfoText = '--';
      this.excerptText = '';
      this.refreshRemoteStatus(snapshot);
      this.refreshSleepTimerState();
      return;
    }

    this.bookTitle = context.bookTitle && context.bookTitle.length > 0 ? context.bookTitle : '听书播放器';
    this.chapterTitle = context.chapterTitle && context.chapterTitle.length > 0
      ? context.chapterTitle
      : `第${context.chapterIndex + 1}章`;
    this.coverUrl = context.coverUrl ?? '';
    const percent = this.calculateProgressPercent(snapshot, context);
    this.progressPercent = percent;
    this.progressText = `${Math.round(percent)}%`;
    this.updateProgressSliderValueFromState();
    const contentLength = Math.max(0, context.content.length);
    const maxCharIndex = Math.max(0, contentLength - 1);
    const rawCharIndex = snapshot.currentCharIndex >= 0 ? snapshot.currentCharIndex : (context.resumeCharIndex ?? 0);
    const safeCharIndex = Math.max(0, Math.min(rawCharIndex, maxCharIndex));
    this.chapterInfoText = `第${context.chapterIndex + 1}章`;
    this.pageInfoText = context.pageIndex >= 0 ? `第${context.pageIndex + 1}页` : '未知页';
    this.charInfoText = contentLength > 0 ? `${safeCharIndex + 1}/${contentLength}` : '--';
    this.chunkInfoText = snapshot.chunkStartCharIndex >= 0 && snapshot.chunkEndCharIndex > snapshot.chunkStartCharIndex
      ? `${snapshot.chunkStartCharIndex + 1}-${snapshot.chunkEndCharIndex}`
      : '--';
    this.engineInfoText = this.getEngineText(String(snapshot.settings.engineType ?? 'SYSTEM'));
    this.speedInfoText = `${(snapshot.settings.speed ?? 1).toFixed(2)}x`;
    this.excerptText = this.buildExcerptText(context.content, safeCharIndex);
    this.refreshRemoteStatus(snapshot);
    this.refreshSleepTimerState();
  }

  private calculateProgressPercent(
    payload: ReadAloudStateSnapshot,
    context: ReadAloudSessionContext
  ): number {
    if (payload.totalDurationMs > 0 && payload.currentPositionMs >= 0) {
      const safePositionMs = Math.max(0, Math.min(payload.currentPositionMs, payload.totalDurationMs));
      return (safePositionMs / Math.max(1, payload.totalDurationMs)) * 100;
    }
    if (!context.content || context.content.length <= 0) {
      return 0;
    }
    const maxCharIndex = Math.max(0, context.content.length - 1);
    const rawCharIndex = payload.currentCharIndex >= 0
      ? payload.currentCharIndex
      : (context.resumeCharIndex ?? 0);
    const safeCharIndex = Math.max(0, Math.min(rawCharIndex, maxCharIndex));
    return (safeCharIndex / Math.max(1, maxCharIndex)) * 100;
  }

  private getStatusText(playbackState: ReadAloudPlaybackState): string {
    if (playbackState === ReadAloudPlaybackState.PLAYING) {
      return '播放中';
    }
    if (playbackState === ReadAloudPlaybackState.PAUSED) {
      return '已暂停';
    }
    if (playbackState === ReadAloudPlaybackState.STOPPED) {
      return '已停止';
    }
    return '未播放';
  }

  private getDetailedStatusText(playbackState: ReadAloudPlaybackState): string {
    const statusText = (AppStorage.get<string>(READ_ALOUD_UI_STATUS_TEXT_KEY) ?? '').trim();
    const detailText = (AppStorage.get<string>(READ_ALOUD_UI_STATUS_DETAIL_KEY) ?? '').trim();
    if (statusText.length > 0 && detailText.length > 0) {
      return `${statusText} · ${detailText}`;
    }
    if (statusText.length > 0) {
      return statusText;
    }
    if (detailText.length > 0) {
      return detailText;
    }
    return this.getStatusText(playbackState);
  }

  private getEngineText(engineType: string): string {
    if (engineType === 'SYSTEM') {
      return '系统 TTS';
    }
    if (engineType === 'LEGADO_COMPAT') {
      return 'Legado 兼容';
    }
    if (engineType === 'REMOTE') {
      return '远程 TTS';
    }
    return engineType;
  }

  private buildExcerptText(content: string, currentCharIndex: number): string {
    if (!content || content.length <= 0) {
      return '暂无可展示文本';
    }
    const safeIndex = Math.max(0, Math.min(currentCharIndex, Math.max(0, content.length - 1)));
    const start = Math.max(0, safeIndex - 28);
    const end = Math.min(content.length, safeIndex + 44);
    const snippet = content.substring(start, end).replace(/\s+/g, ' ').trim();
    if (!snippet) {
      return '暂无可展示文本';
    }
    const prefix = start > 0 ? '…' : '';
    const suffix = end < content.length ? '…' : '';
    return `${prefix}${snippet}${suffix}`;
  }

  private togglePlayPause(): void {
    if (this.isNovelAudioMode) {
      void this.handleNovelAudioTogglePlayPause();
      return;
    }
    if (!this.hasSession) {
      this.getUIContext().getPromptAction().showToast({
        message: '当前没有可播放内容',
        duration: 1500
      });
      return;
    }
    if (this.isPlaying) {
      this.readAloudController.pause('player_toggle');
    } else {
      this.readAloudController.start('player_toggle');
    }
    this.readAloudController.refreshMediaSession();
    this.refreshPlayerState();
  }

  private async handleNovelAudioTogglePlayPause(): Promise<void> {
    if (!this.hasSession) {
      this.getUIContext().getPromptAction().showToast({
        message: '当前没有可播放的听书会话',
        duration: 1400
      });
      return;
    }
    await this.novelAudioSessionManager.togglePlayPause();
    this.refreshPlayerState();
  }

  private skipPrevious(): void {
    if (this.isNovelAudioMode) {
      void this.handleNovelAudioSkipPrevious();
      return;
    }
    if (!this.hasSession) {
      return;
    }
    this.readAloudController.seekByChars(-PLAYER_SKIP_CHARS, 'player_skip_previous');
    this.readAloudController.refreshMediaSession();
    this.refreshPlayerState();
  }

  private async handleNovelAudioSkipPrevious(): Promise<void> {
    if (!this.hasSession) {
      return;
    }
    await this.novelAudioSessionManager.playPreviousChapter(this.isPlaying);
    this.refreshPlayerState();
  }

  private skipNext(): void {
    if (this.isNovelAudioMode) {
      void this.handleNovelAudioSkipNext();
      return;
    }
    if (!this.hasSession) {
      return;
    }
    this.readAloudController.seekByChars(PLAYER_SKIP_CHARS, 'player_skip_next');
    this.readAloudController.refreshMediaSession();
    this.refreshPlayerState();
  }

  private async handleNovelAudioSkipNext(): Promise<void> {
    if (!this.hasSession) {
      return;
    }
    await this.novelAudioSessionManager.playNextChapter(this.isPlaying);
    this.refreshPlayerState();
  }

  private stopPlayback(): void {
    if (this.isNovelAudioMode) {
      void this.handleNovelAudioStop();
      return;
    }
    if (!this.hasSession) {
      return;
    }
    this.readAloudController.stop('player_stop');
    this.readAloudController.refreshMediaSession();
    this.refreshPlayerState();
  }

  private async handleNovelAudioStop(): Promise<void> {
    if (!this.hasSession) {
      return;
    }
    await this.novelAudioSessionManager.stop();
    this.refreshPlayerState();
  }

  private async cacheCurrentNovelAudioChapter(): Promise<void> {
    if (!this.isNovelAudioMode || !this.hasSession) {
      return;
    }
    const success = await this.novelAudioSessionManager.cacheCurrentChapterAudio();
    this.getUIContext().getPromptAction().showToast({
      message: success ? '当前章节听书音频已缓存' : '当前章节听书缓存失败',
      duration: 1400
    });
    this.refreshPlayerState();
  }

  private applyAbilityRouteParams(params: ReadAloudPlayerAbilityParams | null): NovelReaderPageParams | null {
    if (!params) {
      this.playerHostMode = '';
      return null;
    }
    this.playerHostMode = READ_ALOUD_PLAYER_ABILITY_HOST_SINGLETON;
    this.returnHostPage = params.returnHostPage;
    this.previousDisplayMode = params.returnDisplayMode ?? WindowManager.getCurrentMode();
    this.hasCapturedRouteState = false;
    return params.launchParams;
  }

  private resolveRouteParam(rawParam: Object | null | undefined): NovelReaderPageParams | null {
    if (!rawParam) {
      this.playerHostMode = '';
      return null;
    }
    const abilityParams = rawParam as ReadAloudPlayerAbilityParams;
    if (abilityParams.launchParams !== undefined ||
      abilityParams.returnHostPage !== undefined ||
      abilityParams.returnDisplayMode !== undefined) {
      return this.applyAbilityRouteParams(abilityParams);
    }
    this.playerHostMode = '';
    return rawParam as NovelReaderPageParams;
  }

  private terminateIsolatedPlayerAbility(): void {
    try {
      const hostContext = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
      if (!hostContext) {
        logger.warn(TAG, '独立听书播放器退出失败：UIAbilityContext 为空');
        return;
      }
      hostContext.terminateSelf().then((): void => {
        logger.info(TAG, '独立听书播放器实例已退出');
      }).catch((error: Object | string | number | boolean): void => {
        logger.warn(TAG, `独立听书播放器实例退出失败: ${String(error)}`);
      });
    } catch (error) {
      logger.warn(TAG, `独立听书播放器实例退出异常: ${String(error)}`);
    }
  }

  private closePage(): void {
    try {
      if (this.returnHostPage.length > 0) {
        AppStorage.setOrCreate('ReadAloudCurrentHostPage', this.returnHostPage);
      } else {
        AppStorage.setOrCreate('ReadAloudCurrentHostPage', '');
      }
      if (this.shouldUseImmersiveMode()) {
        this.forceReaderImmersiveBeforeExit('closePage');
      } else {
        this.restorePreviousDisplayMode('closePage');
      }
      if (this.playerHostMode === READ_ALOUD_PLAYER_ABILITY_HOST_SINGLETON) {
        this.terminateIsolatedPlayerAbility();
      } else {
        this.pathStack.pop();
      }
    } catch (error) {
      logger.warn(TAG, `返回失败: ${String(error)}`);
    }
  }
  private getSleepDialogThemeColor(
    colorType: 'text_primary' | 'text_secondary' | 'text_tertiary' | 'accent_primary' |
    'comp_background_secondary' | 'comp_divider'
  ): Resource {
    return ThemeAwareHelper.getTestManagementThemedColor(colorType, this.themeState.currentTheme);
  }

  private getDialogMaskColor(): ResourceColor {
    return DialogSurfaceStyleHelper.getPopupMaskColor();
  }

  private getDialogMaskBlurStyle(): BlurStyle {
    return DialogSurfaceStyleHelper.getPopupMaskBlurStyle();
  }

  private getDialogMaskBlurOptions(): BackgroundBlurStyleOptions {
    return DialogSurfaceStyleHelper.getPopupMaskBlurOptions();
  }

  private getDialogMaskBackgroundEffect(): BackgroundEffectOptions | undefined {
    return DialogSurfaceStyleHelper.getPopupMaskBackgroundEffect();
  }

  @Builder
  private buildCoverCard(): void {
    Column({ space: 12 }) {
      if (this.coverUrl.length > 0) {
        Image(this.resolveCoverSource(this.coverUrl))
          .width(188)
          .height(252)
          .objectFit(ImageFit.Cover)
          .borderRadius(16)
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.book'))
            .fontSize(60)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width(188)
        .height(252)
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.background_secondary'))
        .borderRadius(16)
      }

      Text(this.bookTitle)
        .fontSize(22)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textAlign(TextAlign.Center)

      Text(this.chapterTitle)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(2)
        .textAlign(TextAlign.Center)

      Text(this.statusText)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(this.isPlaying ? $r('app.color.accent_primary') : $r('app.color.text_secondary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 8, left: 8, right: 8, bottom: 8 })
    .backgroundColor('rgba(255,255,255,0.02)')
    .borderRadius(20)
    .border({ width: 1, color: 'rgba(255,255,255,0.08)' })
  }

  @Builder
  private buildRemoteStatusCard(): void {
    Column({ space: 10 }) {
      Row() {
        Text('远程音频状态')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.isRemoteEngineActive() ? '实时更新' : '仅远程 TTS 可用')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.isRemoteEngineActive() ? $r('app.color.accent_primary') : $r('app.color.text_secondary'))
      }
      .width('100%')

      Row() {
        Text('当前分片')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.remoteSegmentText)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')

      Row() {
        Text('已缓存分片')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.remoteCacheSegmentText)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')

      Row() {
        Text('已缓存体积')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.remoteCacheBytesText)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')

      Text(
        this.isRemoteEngineActive()
          ? '播放器会随着章节播放自动刷新分片与缓存进度，方便你判断当前章节的离线可用程度。'
          : '当前没有启用远程 TTS，引擎切换到远程后，这里会显示章节分片与自动缓存进度。'
      )
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .lineHeight(20)
        .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor('rgba(255,255,255,0.02)')
    .borderRadius(16)
    .border({ width: 1, color: 'rgba(255,255,255,0.08)' })
  }

  @Builder
  private buildSleepTimerCard(): void {
    Column({ space: 12 }) {
      Row() {
        Text('定时关闭')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.sleepTimerText)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(this.sleepTimerActive ? $r('app.color.accent_primary') : $r('app.color.text_primary'))
      }
      .width('100%')

      Text('支持快速设置 5、15、30 分钟，以及 1 到 2 小时的预设，也可以输入自定义时长。')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .lineHeight(20)
        .width('100%')

      Row({ space: 12 }) {
        Button('设置定时')
          .height(40)
          .layoutWeight(1)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .backgroundColor($r('app.color.accent_primary'))
          .fontColor(Color.White)
          .borderRadius(12)
          .scale({ x: this.resolveButtonScale('sleep_timer_open'), y: this.resolveButtonScale('sleep_timer_open') })
          .animation({ duration: 150, curve: Curve.EaseOut })
          .onClick(() => {
            this.runAnimatedButtonAction('sleep_timer_open', () => this.showSleepTimerDialogWithAnimation());
          })

        if (this.sleepTimerActive) {
          Button('取消定时')
            .height(40)
            .layoutWeight(1)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .backgroundColor($r('app.color.background_secondary'))
            .fontColor($r('app.color.text_primary'))
            .borderRadius(12)
            .scale({ x: this.resolveButtonScale('sleep_timer_cancel'), y: this.resolveButtonScale('sleep_timer_cancel') })
            .animation({ duration: 150, curve: Curve.EaseOut })
            .onClick(() => {
              this.runAnimatedButtonAction('sleep_timer_cancel', () => this.cancelSleepTimer());
            })
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.background_secondary'))
    .borderRadius(16)
  }

  @Builder
  private buildSleepTimerDialog(): void {
    Stack({ alignContent: Alignment.Center }) {
      SourceDialogScaffold({
        themeState: this.themeState,
        onMaskTap: () => this.hideSleepTimerDialogWithAnimation(),
        dialogWidth: '88%',
        maxWidth: 520,
        maxHeight: '82%',
        contentPadding: 20,
        dialogRadius: 24,
        zIndexValue: 3000,
        useMaskBlur: true,
        maskBlurStyle: this.getDialogMaskBlurStyle(),
        maskBlurOptions: this.getDialogMaskBlurOptions(),
        maskColor: this.getDialogMaskColor(),
        maskBackgroundEffect: this.getDialogMaskBackgroundEffect()
      }) {
        Column({ space: 16 }) {
          Row() {
            Text('定时关闭')
              .fontSize(20)
              .fontFamily(this.appFontFamily)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getSleepDialogThemeColor('text_primary'))
            Blank()
            Button('关闭')
              .height(34)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .backgroundColor(this.getSleepDialogThemeColor('comp_background_secondary'))
              .fontColor(this.getSleepDialogThemeColor('text_primary'))
              .borderRadius(17)
              .scale({ x: this.resolveButtonScale('sleep_dialog_close'), y: this.resolveButtonScale('sleep_dialog_close') })
              .animation({ duration: 150, curve: Curve.EaseOut })
              .onClick(() => {
                this.runAnimatedButtonAction('sleep_dialog_close', () => this.hideSleepTimerDialogWithAnimation());
              })
          }
          .width('100%')

          Text('选择一个预设时长，或输入自定义分钟/小时。时间到后会自动停止当前听书播放。')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getSleepDialogThemeColor('text_secondary'))
            .lineHeight(21)
            .width('100%')

          Column({ space: 10 }) {
            Row({ space: 10 }) {
              Button('5 分钟')
                .height(42)
                .layoutWeight(1)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .backgroundColor(this.getSleepDialogThemeColor('comp_background_secondary'))
                .fontColor(this.getSleepDialogThemeColor('text_primary'))
                .borderRadius(12)
                .scale({ x: this.resolveButtonScale('sleep_preset_5m'), y: this.resolveButtonScale('sleep_preset_5m') })
                .animation({ duration: 150, curve: Curve.EaseOut })
                .onClick(() => {
                  this.runAnimatedButtonAction('sleep_preset_5m', () => this.applySleepTimer(5 * 60 * 1000));
                })

              Button('15 分钟')
                .height(42)
                .layoutWeight(1)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .backgroundColor(this.getSleepDialogThemeColor('comp_background_secondary'))
                .fontColor(this.getSleepDialogThemeColor('text_primary'))
                .borderRadius(12)
                .scale({ x: this.resolveButtonScale('sleep_preset_15m'), y: this.resolveButtonScale('sleep_preset_15m') })
                .animation({ duration: 150, curve: Curve.EaseOut })
                .onClick(() => {
                  this.runAnimatedButtonAction('sleep_preset_15m', () => this.applySleepTimer(15 * 60 * 1000));
                })
            }
            .width('100%')

            Row({ space: 10 }) {
              Button('30 分钟')
                .height(42)
                .layoutWeight(1)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .backgroundColor(this.getSleepDialogThemeColor('comp_background_secondary'))
                .fontColor(this.getSleepDialogThemeColor('text_primary'))
                .borderRadius(12)
                .scale({ x: this.resolveButtonScale('sleep_preset_30m'), y: this.resolveButtonScale('sleep_preset_30m') })
                .animation({ duration: 150, curve: Curve.EaseOut })
                .onClick(() => {
                  this.runAnimatedButtonAction('sleep_preset_30m', () => this.applySleepTimer(30 * 60 * 1000));
                })

              Button('1 小时')
                .height(42)
                .layoutWeight(1)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .backgroundColor(this.getSleepDialogThemeColor('comp_background_secondary'))
                .fontColor(this.getSleepDialogThemeColor('text_primary'))
                .borderRadius(12)
                .scale({ x: this.resolveButtonScale('sleep_preset_1h'), y: this.resolveButtonScale('sleep_preset_1h') })
                .animation({ duration: 150, curve: Curve.EaseOut })
                .onClick(() => {
                  this.runAnimatedButtonAction('sleep_preset_1h', () => this.applySleepTimer(60 * 60 * 1000));
                })
            }
            .width('100%')

            Button('2 小时')
              .height(42)
              .width('100%')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .backgroundColor(this.getSleepDialogThemeColor('comp_background_secondary'))
              .fontColor(this.getSleepDialogThemeColor('text_primary'))
              .borderRadius(12)
              .scale({ x: this.resolveButtonScale('sleep_preset_2h'), y: this.resolveButtonScale('sleep_preset_2h') })
              .animation({ duration: 150, curve: Curve.EaseOut })
              .onClick(() => {
                this.runAnimatedButtonAction('sleep_preset_2h', () => this.applySleepTimer(2 * 60 * 60 * 1000));
              })
          }
          .width('100%')

          Column({ space: 12 }) {
            Text('自定义时长')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(this.getSleepDialogThemeColor('text_primary'))
              .width('100%')
              .textAlign(TextAlign.Start)

            TextInput({ text: this.customSleepTimerValue, placeholder: '请输入数字' })
              .height(46)
              .width('100%')
              .type(InputType.Number)
              .fontSize(15)
              .fontFamily(this.appFontFamily)
              .fontColor(this.getSleepDialogThemeColor('text_primary'))
              .placeholderColor(this.getSleepDialogThemeColor('text_tertiary'))
              .backgroundColor(this.getSleepDialogThemeColor('comp_background_secondary'))
              .borderRadius(12)
              .border({ width: 1, color: this.getSleepDialogThemeColor('comp_divider') })
              .onChange((value: string) => {
                this.customSleepTimerValue = value.replace(/[^0-9]/g, '');
              })

            Row({ space: 10 }) {
              Button('分钟')
                .height(40)
                .layoutWeight(1)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .backgroundColor(
                  this.customSleepTimerUnit === 'minute'
                    ? this.getSleepDialogThemeColor('accent_primary')
                    : this.getSleepDialogThemeColor('comp_background_secondary')
                )
                .fontColor(
                  this.customSleepTimerUnit === 'minute'
                    ? Color.White
                    : this.getSleepDialogThemeColor('text_primary')
                )
                .borderRadius(12)
                .scale({ x: this.resolveButtonScale('sleep_custom_minute'), y: this.resolveButtonScale('sleep_custom_minute') })
                .animation({ duration: 150, curve: Curve.EaseOut })
                .onClick(() => {
                  this.runAnimatedButtonAction('sleep_custom_minute', () => {
                    this.customSleepTimerUnit = 'minute';
                  });
                })

              Button('小时')
                .height(40)
                .layoutWeight(1)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .backgroundColor(
                  this.customSleepTimerUnit === 'hour'
                    ? this.getSleepDialogThemeColor('accent_primary')
                    : this.getSleepDialogThemeColor('comp_background_secondary')
                )
                .fontColor(
                  this.customSleepTimerUnit === 'hour'
                    ? Color.White
                    : this.getSleepDialogThemeColor('text_primary')
                )
                .borderRadius(12)
                .scale({ x: this.resolveButtonScale('sleep_custom_hour'), y: this.resolveButtonScale('sleep_custom_hour') })
                .animation({ duration: 150, curve: Curve.EaseOut })
                .onClick(() => {
                  this.runAnimatedButtonAction('sleep_custom_hour', () => {
                    this.customSleepTimerUnit = 'hour';
                  });
                })
            }
            .width('100%')

            Button('确认设置')
              .height(44)
              .width('100%')
              .fontSize(15)
              .fontFamily(this.appFontFamily)
              .backgroundColor(this.getSleepDialogThemeColor('accent_primary'))
              .fontColor(Color.White)
              .borderRadius(14)
              .scale({ x: this.resolveButtonScale('sleep_custom_apply'), y: this.resolveButtonScale('sleep_custom_apply') })
              .animation({ duration: 150, curve: Curve.EaseOut })
              .onClick(() => {
                this.runAnimatedButtonAction('sleep_custom_apply', () => this.applyCustomSleepTimer());
              })
          }
          .width('100%')
        }
        .width('100%')
        .scale({ x: this.sleepTimerDialogScale, y: this.sleepTimerDialogScale })
        .animation({ duration: 180, curve: Curve.EaseOut })
      }
    }
    .width('100%')
    .height('100%')
    .opacity(this.sleepTimerDialogOpacity)
    .animation({ duration: 180, curve: Curve.EaseOut })
  }

  @Builder
  private buildProgressCard(): void {
    Column({ space: 10 }) {
      Row() {
        Text('播放进度')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.isProgressDragging ? `${Math.round(this.progressSliderValue)}%` : this.progressText)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')

      Slider({
        value: this.progressSliderValue,
        min: 0,
        max: 100,
        step: 1,
        style: SliderStyle.OutSet
      })
        .width('100%')
        .trackColor($r('app.color.divider_primary'))
        .selectedColor($r('app.color.accent_primary'))
        .blockColor($r('app.color.accent_primary'))
        .enabled(this.hasSession)
        .onChange((value: number, mode: SliderChangeMode) => {
          this.onProgressSliderChange(value, mode);
        })
        .animation({ duration: 150, curve: Curve.EaseOut })

      Text(this.getProgressHintText())
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .opacity(this.hasSession ? 1 : 0.6)
        .animation({ duration: 180, curve: Curve.EaseOut })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.background_secondary'))
    .borderRadius(16)
    .scale({ x: this.isProgressDragging ? 1.01 : 1, y: this.isProgressDragging ? 1.01 : 1 })
    .animation({ duration: 180, curve: Curve.EaseOut })
  }

  @Builder
  private buildSessionInfoCard(): void {
    Column({ space: 10 }) {
      Text('播放详情')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      Row() {
        Text('章节')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.chapterInfoText)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')

      Row() {
        Text('页面')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.pageInfoText)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')

      Row() {
        Text('字符')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.charInfoText)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')

      Row() {
        Text('分段')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.chunkInfoText)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')

      Row() {
        Text('引擎 / 语速')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(`${this.engineInfoText} · ${this.speedInfoText}`)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor('rgba(255,255,255,0.02)')
    .borderRadius(16)
    .border({ width: 1, color: 'rgba(255,255,255,0.08)' })
  }

  @Builder
  private buildInfoPanelSection(): void {
    Column({ space: 10 }) {
      Row() {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.info_circle'))
            .fontSize(14)
            .fontColor([$r('app.color.text_secondary')])
          Text('信息展示面板')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor($r('app.color.text_secondary'))
        }
        Blank()
        Button() {
          Row({ space: 4 }) {
            Text(this.isInfoPanelCollapsed ? '展开' : '收起')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.text_primary'))
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(12)
              .fontColor([$r('app.color.text_primary')])
              .rotate({ angle: this.isInfoPanelCollapsed ? -90 : 0 })
              .animation({ duration: 220, curve: Curve.EaseInOut })
          }
        }
        .height(30)
        .padding({ left: 12, right: 12 })
        .backgroundColor($r('app.color.background_secondary'))
        .borderRadius(15)
        .scale({ x: this.resolveButtonScale('toggle_info_panel'), y: this.resolveButtonScale('toggle_info_panel') })
        .animation({ duration: 150, curve: Curve.EaseOut })
        .onClick(() => {
          this.runAnimatedButtonAction('toggle_info_panel', () => this.toggleInfoPanelCollapsed());
        })
      }
      .width('100%')

      if (!this.isInfoPanelCollapsed) {
        Column({ space: 12 }) {
          this.buildSessionInfoCard()
          if (!this.isNovelAudioMode) {
            this.buildRemoteStatusCard()
          }
          this.buildExcerptCard()
        }
        .width('100%')
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -10 })))
      }
    }
    .width('100%')
    .animation({ duration: 260, curve: Curve.EaseInOut })
  }

  @Builder
  private buildExcerptCard(): void {
    Column({ space: 8 }) {
      Text('当前朗读片段')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Start)
      Text(this.excerptText.length > 0 ? this.excerptText : '暂无可展示文本')
        .fontSize(15)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_primary'))
        .lineHeight(24)
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.background_secondary'))
    .borderRadius(16)
  }

  @Builder
  private buildControlCard(): void {
    Column({ space: 14 }) {
      Row({ space: 16 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(20)
            .fontColor([$r('app.color.text_primary')])
        }
        .width(52)
        .height(52)
        .borderRadius(26)
        .backgroundColor($r('app.color.background_secondary'))
        .enabled(this.hasSession)
        .scale({ x: this.resolveButtonScale('control_previous'), y: this.resolveButtonScale('control_previous') })
        .animation({ duration: 150, curve: Curve.EaseOut })
        .onClick(() => {
          this.runAnimatedButtonAction('control_previous', () => this.skipPrevious());
        })

        Button() {
          SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
            .fontSize(28)
            .fontColor([Color.White])
        }
        .width(72)
        .height(72)
        .borderRadius(36)
        .backgroundColor($r('app.color.accent_primary'))
        .enabled(this.hasSession)
        .scale({ x: this.resolveButtonScale('control_play_pause'), y: this.resolveButtonScale('control_play_pause') })
        .animation({ duration: 150, curve: Curve.EaseOut })
        .onClick(() => {
          this.runAnimatedButtonAction('control_play_pause', () => this.togglePlayPause());
        })

        Button() {
          SymbolGlyph($r('sys.symbol.arrow_right'))
            .fontSize(20)
            .fontColor([$r('app.color.text_primary')])
        }
        .width(52)
        .height(52)
        .borderRadius(26)
        .backgroundColor($r('app.color.background_secondary'))
        .enabled(this.hasSession)
        .scale({ x: this.resolveButtonScale('control_next'), y: this.resolveButtonScale('control_next') })
        .animation({ duration: 150, curve: Curve.EaseOut })
        .onClick(() => {
          this.runAnimatedButtonAction('control_next', () => this.skipNext());
        })
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')

      Button('停止播放')
        .height(38)
        .width('100%')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .backgroundColor($r('app.color.background_secondary'))
        .fontColor($r('app.color.text_primary'))
        .enabled(this.hasSession)
        .scale({ x: this.resolveButtonScale('control_stop'), y: this.resolveButtonScale('control_stop') })
        .animation({ duration: 150, curve: Curve.EaseOut })
        .onClick(() => {
          this.runAnimatedButtonAction('control_stop', () => this.stopPlayback());
        })

      if (this.isNovelAudioMode) {
        Button(this.speedInfoText === '缓存中' ? '正在缓存本章...' : '缓存当前章节')
          .height(38)
          .width('100%')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .backgroundColor($r('app.color.background_secondary'))
          .fontColor($r('app.color.text_primary'))
          .enabled(this.hasSession && this.speedInfoText !== '缓存中')
          .scale({ x: this.resolveButtonScale('control_cache_chapter'), y: this.resolveButtonScale('control_cache_chapter') })
          .animation({ duration: 150, curve: Curve.EaseOut })
          .onClick(() => {
            this.runAnimatedButtonAction('control_cache_chapter', () => {
              void this.cacheCurrentNovelAudioChapter();
            });
          })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('rgba(255,255,255,0.02)')
    .borderRadius(16)
    .border({ width: 1, color: 'rgba(255,255,255,0.08)' })
  }

  build() {
    HdsNavDestination() {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Circle()
          .width(280)
          .height(280)
          .fill('rgba(24,144,255,0.10)')
          .position({ x: -100, y: -90 })

        Circle()
          .width(220)
          .height(220)
          .fill('rgba(24,144,255,0.06)')
          .position({ x: '100%', y: '75%' })
          .translate({ x: -170, y: -120 })

        Scroll() {
          Column({ space: 14 }) {
            Blank().height(PLAYER_TOP_CONTENT_PADDING)
            this.buildCoverCard()
            this.buildProgressCard()
            this.buildInfoPanelSection()
            this.buildSleepTimerCard()
            this.buildControlCard()
            Blank()
          }
          .width('100%')
          .padding({ top: 18, left: 16, right: 16, bottom: 20 })
          .opacity(this.entered ? 1 : 0)
          .translate({ y: this.entered ? 0 : 20 })
          .animation({ duration: 260, curve: Curve.EaseOut })
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)

        if (this.showSleepTimerDialog) {
          this.buildSleepTimerDialog()
        }
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({
      padding: {
        start: LengthMetrics.vp(2),
        end: LengthMetrics.vp(2)
      },
      style: {
        originalStyle: {
          backgroundStyle: { backgroundColor: $r('app.color.background_secondary') },
          contentStyle: {
            titleStyle: {
              mainTitleColor: $r('app.color.text_primary'),
              subTitleColor: $r('app.color.text_secondary')
            },
            backIconStyle: {
              backgroundColor: $r('app.color.comp_background_tertiary'),
              iconColor: $r('app.color.text_primary')
            }
          }
        }
      },
      content: {
        title: {
          mainTitle: '听书播放器'
        }
      }
    })
    .hideTitleBar(true)
    .backgroundColor(Color.Transparent)
    .mode(NavDestinationMode.STANDARD)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const routeParam = this.resolveRouteParam(context.pathInfo.param as Object | null);
      void this.initializeNovelAudioSessionIfNeeded(routeParam);
      this.entered = false;
      setTimeout(() => {
        this.entered = true;
      }, 20);
    })
    .onShown(() => {
      this.captureRouteState('onShown');
      this.applyPreferredDisplayMode('onShown');
      this.scheduleDisplayRestore('onShown');
      AppStorage.setOrCreate('ReadAloudCurrentHostPage', 'ReadAloudPlayerPage');
      AppStorage.setOrCreate(READ_ALOUD_FLOATING_BALL_SUPPRESSED_KEY, true);
      this.refreshPlayerState();
      if (!this.isNovelAudioMode) {
        this.readAloudController.refreshMediaSession();
      }
    })
    .onBackPressed(() => {
      if (this.showSleepTimerDialog) {
        this.hideSleepTimerDialogWithAnimation();
        return true;
      }
      this.closePage();
      return true;
    })
  }
}
