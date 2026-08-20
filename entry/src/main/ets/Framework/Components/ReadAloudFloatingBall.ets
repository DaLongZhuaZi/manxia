import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { display } from '@kit.ArkUI';
import { ReadAloudController } from '../ReadAloud/ReadAloudController';
import { eventBus, GameEvent, IEventPayload } from '../EventBus';
import { ReadAloudPlaybackState, ReadAloudSessionContext, ReadAloudStateSnapshot } from '../ReadAloud/ReadAloudTypes';
import {
  getNovelAudioReadAloudSessionManager,
  NovelAudioReadAloudSnapshot,
  NovelAudioReadAloudStateListener
} from '../ReadAloud/NovelAudioReadAloudSessionManager';
import { WindowManager, DisplayMode } from 'manxia_theme/src/main/ets/Utils/WindowManager';
import { openReadAloudPlayerInIsolatedAbility } from '../ReadAloud/ReadAloudPlayerAbilityLauncher';
import {
  getHoldingAwarenessManager,
  HoldingAwarenessFeature,
  HoldingAwarenessManager,
  HoldingUiAnchor
} from '../Managers/HoldingAwarenessManager';

const TAG = 'ReadAloudFloatingBall';
const FLOATING_BALL_REFRESH_INTERVAL_MS: number = 400;
const FLOATING_BALL_MARQUEE_INTERVAL_MS: number = 220;
const FLOATING_BALL_MARQUEE_WINDOW_SIZE: number = 18;
const FLOATING_BALL_LONG_PRESS_EXIT_HOLD_MS: number = 3000;
const FLOATING_BALL_LONG_PRESS_EXIT_AUTO_MS: number = 900;
const FLOATING_BALL_DRAG_START_THRESHOLD_PX: number = 10;
const FLOATING_BALL_DEFAULT_LEFT_X: number = 20;
const FLOATING_BALL_DEFAULT_TOP_Y: number = 280;
const FLOATING_BALL_ESTIMATED_WIDTH: number = 276;
const FLOATING_BALL_EXIT_HINT_TEXT: string = '听书悬浮球即将退出';
const READ_ALOUD_UI_STATUS_TEXT_KEY = 'ReadAloudUiStatusText';
const READ_ALOUD_UI_STATUS_DETAIL_KEY = 'ReadAloudUiStatusDetail';
const READ_ALOUD_UI_STATUS_PHASE_KEY = 'ReadAloudUiStatusPhase';
const READ_ALOUD_FLOATING_BALL_SUPPRESSED_KEY = 'ReadAloudFloatingBallSuppressed';

@Component
export struct ReadAloudFloatingBall {
  @State private isVisible: boolean = false;
  @State private isPlaying: boolean = false;
  @State private showBackRouteIcon: boolean = false;
  @State private ballX: number = FLOATING_BALL_DEFAULT_LEFT_X;
  @State private ballY: number = FLOATING_BALL_DEFAULT_TOP_Y;
  @State private isDragging: boolean = false;
  @State private marqueeText: string = '';
  @State private progressSummaryText: string = '';
  @State private currentPhase: string = '';
  @State private isExitingByLongPress: boolean = false;
  @StorageProp('holding_awareness_preferred_anchor') @Watch('onHoldingAwareFloatingBallSettingChanged')
  private holdingAwarenessPreferredAnchor: HoldingUiAnchor = HoldingUiAnchor.RIGHT;
  @StorageProp('holding_awareness_enabled') @Watch('onHoldingAwareFloatingBallSettingChanged')
  private holdingAwarenessEnabled: boolean = true;
  @StorageProp('holding_awareness_read_aloud_floating_ball_enabled') @Watch('onHoldingAwareFloatingBallSettingChanged')
  private holdingAwarenessReadAloudFloatingBallEnabled: boolean = true;

  private readAloudController: ReadAloudController = ReadAloudController.getInstance();
  private novelAudioSessionManager = getNovelAudioReadAloudSessionManager();
  private holdingAwarenessManager: HoldingAwarenessManager = getHoldingAwarenessManager();
  private dragStartX: number = 0;
  private dragStartY: number = 0;
  private ballStartX: number = 0;
  private ballStartY: number = 0;
  private stateRefreshTimer: number = -1;
  private marqueeTimer: number = -1;
  private marqueeSourceText: string = '';
  private marqueeOffset: number = 0;
  private longPressExitHoldTimer: number = -1;
  private longPressExitAutoTimer: number = -1;
  private activeSessionKey: string = '';
  private dismissedSessionKey: string = '';
  private hasUserDraggedBall: boolean = false;

  private onReadAloudStateChanged: (_payload: IEventPayload) => void = (): void => {
    this.refreshBallState();
  };
  private onNovelAudioSessionChanged: NovelAudioReadAloudStateListener = (_snapshot: NovelAudioReadAloudSnapshot): void => {
    this.refreshBallState();
  };

  aboutToAppear(): void {
    eventBus.subscribe(GameEvent.READ_ALOUD_STATE_CHANGED, this.onReadAloudStateChanged);
    this.novelAudioSessionManager.subscribe(this.onNovelAudioSessionChanged);
    this.refreshBallState();
    if (this.stateRefreshTimer >= 0) {
      clearInterval(this.stateRefreshTimer);
    }
    this.stateRefreshTimer = setInterval(() => {
      this.refreshBallState();
    }, FLOATING_BALL_REFRESH_INTERVAL_MS);
    if (this.marqueeTimer >= 0) {
      clearInterval(this.marqueeTimer);
    }
    this.marqueeTimer = setInterval(() => {
      this.updateMarqueeText();
    }, FLOATING_BALL_MARQUEE_INTERVAL_MS);
  }

  aboutToDisappear(): void {
    eventBus.unsubscribe(GameEvent.READ_ALOUD_STATE_CHANGED, this.onReadAloudStateChanged);
    this.novelAudioSessionManager.unsubscribe(this.onNovelAudioSessionChanged);
    if (this.stateRefreshTimer >= 0) {
      clearInterval(this.stateRefreshTimer);
      this.stateRefreshTimer = -1;
    }
    if (this.marqueeTimer >= 0) {
      clearInterval(this.marqueeTimer);
      this.marqueeTimer = -1;
    }
    this.clearLongPressExitHoldTimer();
    this.clearLongPressExitAutoTimer();
  }

  private resolveNovelAudioSessionKey(snapshot: NovelAudioReadAloudSnapshot): string {
    if (!snapshot.hasSession) {
      return '';
    }
    return `${snapshot.sourceId}_${snapshot.bookId}`;
  }

  private resolveTextSessionKey(context: ReadAloudSessionContext | null): string {
    if (!context || context.bookId.length <= 0) {
      return '';
    }
    return context.bookId;
  }

  private updateActiveSessionKey(sessionKey: string): void {
    const previousSessionKey: string = this.activeSessionKey;
    if (previousSessionKey.length > 0 && previousSessionKey !== sessionKey && this.isExitingByLongPress) {
      this.isExitingByLongPress = false;
      this.clearLongPressExitHoldTimer();
      this.clearLongPressExitAutoTimer();
    }
    this.activeSessionKey = sessionKey;
    if (sessionKey.length <= 0) {
      this.dismissedSessionKey = '';
      this.isExitingByLongPress = false;
      this.clearLongPressExitHoldTimer();
      this.clearLongPressExitAutoTimer();
      return;
    }
    if (this.dismissedSessionKey.length > 0 && this.dismissedSessionKey !== sessionKey) {
      this.dismissedSessionKey = '';
    }
  }

  private isSessionDismissed(sessionKey: string): boolean {
    return sessionKey.length > 0 && this.dismissedSessionKey === sessionKey;
  }

  private getDisplayWidthVp(): number {
    try {
      const info = display.getDefaultDisplaySync();
      const density = info.densityDPI / 160;
      if (density > 0) {
        return info.width / density;
      }
    } catch (_error) {
      logger.debug(TAG, '读取屏幕宽度失败，听书悬浮球使用默认宽度');
    }
    return 360;
  }

  private shouldUseHoldingAwareReadAloudBall(): boolean {
    if (!this.holdingAwarenessEnabled || !this.holdingAwarenessReadAloudFloatingBallEnabled) {
      return false;
    }
    return this.holdingAwarenessManager.isFeatureEnabled(HoldingAwarenessFeature.READ_ALOUD_FLOATING_BALL);
  }

  private getHoldingAwareReadAloudBallX(): number {
    if (!this.shouldUseHoldingAwareReadAloudBall()) {
      return FLOATING_BALL_DEFAULT_LEFT_X;
    }
    if (this.holdingAwarenessPreferredAnchor === HoldingUiAnchor.LEFT) {
      return FLOATING_BALL_DEFAULT_LEFT_X;
    }
    const displayWidth = this.getDisplayWidthVp();
    const rightX = displayWidth - FLOATING_BALL_ESTIMATED_WIDTH - FLOATING_BALL_DEFAULT_LEFT_X;
    return rightX > FLOATING_BALL_DEFAULT_LEFT_X ? rightX : FLOATING_BALL_DEFAULT_LEFT_X;
  }

  private syncHoldingAwareBallPosition(canShow: boolean): void {
    if (!canShow) {
      this.hasUserDraggedBall = false;
      return;
    }
    if (this.hasUserDraggedBall) {
      return;
    }
    this.ballX = this.getHoldingAwareReadAloudBallX();
  }

  onHoldingAwareFloatingBallSettingChanged(changedPropertyName?: string): void {
    if (changedPropertyName) {
      logger.debug(TAG, `听书悬浮球握姿设置变化：${changedPropertyName}`);
    }
    this.syncHoldingAwareBallPosition(this.isVisible);
  }

  private applyLongPressExitPresentation(canShow: boolean): void {
    this.isVisible = canShow;
    if (!canShow) {
      this.syncHoldingAwareBallPosition(false);
      return;
    }
    this.currentPhase = 'exit_pending';
    this.marqueeSourceText = FLOATING_BALL_EXIT_HINT_TEXT;
    this.marqueeOffset = 0;
    this.marqueeText = FLOATING_BALL_EXIT_HINT_TEXT;
    this.progressSummaryText = '长按已触发，悬浮球将自动退出';
  }

  private refreshBallState(): void {
    const novelAudioSnapshot = this.novelAudioSessionManager.getSnapshot();
    const isSuppressed = AppStorage.get<boolean>(READ_ALOUD_FLOATING_BALL_SUPPRESSED_KEY) === true;
    if (novelAudioSnapshot.hasSession) {
      const sessionKey = this.resolveNovelAudioSessionKey(novelAudioSnapshot);
      this.updateActiveSessionKey(sessionKey);
      this.refreshNovelAudioBallState(novelAudioSnapshot, isSuppressed, sessionKey);
      return;
    }

    const snapshot = this.readAloudController.getSnapshot();
    const context = this.readAloudController.getContextSnapshot();
    const hasValidContext = snapshot.hasContext && context !== null;
    const hasActivePlayback = snapshot.playbackState === ReadAloudPlaybackState.PLAYING ||
      snapshot.playbackState === ReadAloudPlaybackState.PAUSED;
    const sessionKey = hasValidContext ? this.resolveTextSessionKey(context) : '';
    this.updateActiveSessionKey(sessionKey);
    if (!hasValidContext || !hasActivePlayback) {
      this.isVisible = false;
      this.isDragging = false;
      this.syncHoldingAwareBallPosition(false);
      this.clearLongPressExitHoldTimer();
      return;
    }
    const dismissed = this.isSessionDismissed(sessionKey);
    const canShow = !isSuppressed && !dismissed;
    if (this.isExitingByLongPress) {
      this.applyLongPressExitPresentation(canShow);
      return;
    }
    this.isVisible = canShow;
    if (!canShow) {
      this.syncHoldingAwareBallPosition(false);
      return;
    }
    this.syncHoldingAwareBallPosition(true);
    this.isPlaying = snapshot.playbackState === ReadAloudPlaybackState.PLAYING;
    this.showBackRouteIcon = this.isPlayerHostPage();
    this.currentPhase = (AppStorage.get<string>(READ_ALOUD_UI_STATUS_PHASE_KEY) ?? '').trim();
    const statusText = this.resolveStatusText(snapshot);
    if (statusText !== this.marqueeSourceText) {
      this.marqueeSourceText = statusText;
      this.marqueeOffset = 0;
      this.marqueeText = this.buildMarqueeText();
    } else if (this.marqueeText.length <= 0) {
      this.marqueeText = this.buildMarqueeText();
    }
    this.progressSummaryText = this.buildProgressSummary(snapshot, context);
  }

  private refreshNovelAudioBallState(snapshot: NovelAudioReadAloudSnapshot, isSuppressed: boolean, sessionKey: string): void {
    const dismissed = this.isSessionDismissed(sessionKey);
    const canShow = !isSuppressed && snapshot.hasSession && !dismissed;
    if (this.isExitingByLongPress) {
      this.applyLongPressExitPresentation(canShow);
      return;
    }
    this.isVisible = canShow;
    if (!canShow) {
      this.syncHoldingAwareBallPosition(false);
      return;
    }
    this.syncHoldingAwareBallPosition(true);
    this.isPlaying = snapshot.isPlaying;
    this.showBackRouteIcon = this.isPlayerHostPage();
    this.currentPhase = this.resolveNovelAudioPhase(snapshot);
    const statusText = this.resolveNovelAudioStatusText(snapshot);
    if (statusText !== this.marqueeSourceText) {
      this.marqueeSourceText = statusText;
      this.marqueeOffset = 0;
      this.marqueeText = this.buildMarqueeText();
    } else if (this.marqueeText.length <= 0) {
      this.marqueeText = this.buildMarqueeText();
    }
    this.progressSummaryText = this.buildNovelAudioProgressSummary(snapshot);
  }

  private clearLongPressExitHoldTimer(): void {
    if (this.longPressExitHoldTimer >= 0) {
      clearTimeout(this.longPressExitHoldTimer);
      this.longPressExitHoldTimer = -1;
    }
  }

  private clearLongPressExitAutoTimer(): void {
    if (this.longPressExitAutoTimer >= 0) {
      clearTimeout(this.longPressExitAutoTimer);
      this.longPressExitAutoTimer = -1;
    }
  }

  private startLongPressExitHoldDetection(): void {
    if (this.isExitingByLongPress || this.activeSessionKey.length <= 0 || this.isSessionDismissed(this.activeSessionKey)) {
      return;
    }
    this.clearLongPressExitHoldTimer();
    this.longPressExitHoldTimer = setTimeout(() => {
      this.handleLongPressExitTriggered();
    }, FLOATING_BALL_LONG_PRESS_EXIT_HOLD_MS);
  }

  private handleLongPressExitTriggered(): void {
    if (
      this.isExitingByLongPress ||
      this.isDragging ||
      this.activeSessionKey.length <= 0 ||
      this.isSessionDismissed(this.activeSessionKey)
    ) {
      return;
    }
    this.isExitingByLongPress = true;
    this.applyLongPressExitPresentation(true);
    this.clearLongPressExitHoldTimer();
    this.clearLongPressExitAutoTimer();
    logger.info(TAG, `听书悬浮球长按触发退出倒计时: 会话=${this.activeSessionKey}`);
    this.longPressExitAutoTimer = setTimeout(() => {
      this.finalizeLongPressExit();
    }, FLOATING_BALL_LONG_PRESS_EXIT_AUTO_MS);
  }

  private finalizeLongPressExit(): void {
    if (this.activeSessionKey.length > 0) {
      this.dismissedSessionKey = this.activeSessionKey;
    }
    this.isExitingByLongPress = false;
    this.isVisible = false;
    this.isDragging = false;
    this.syncHoldingAwareBallPosition(false);
    this.clearLongPressExitHoldTimer();
    this.clearLongPressExitAutoTimer();
    logger.info(TAG, `听书悬浮球已自动退出: 会话=${this.dismissedSessionKey}`);
  }

  private resolveNovelAudioPhase(snapshot: NovelAudioReadAloudSnapshot): string {
    if (snapshot.loadErrorMessage.length > 0) {
      return 'error';
    }
    if (snapshot.isLoading) {
      return 'preparing';
    }
    if (snapshot.isCachingCurrentChapterAudio) {
      return 'buffering';
    }
    if (snapshot.isPlaying) {
      return 'playing';
    }
    return snapshot.hasSession ? 'paused' : '';
  }

  private resolveNovelAudioStatusText(snapshot: NovelAudioReadAloudSnapshot): string {
    const chapterLabel = snapshot.chapterTitle.length > 0
      ? snapshot.chapterTitle
      : `第 ${snapshot.chapterIndex + 1} 章`;
    if (snapshot.loadErrorMessage.length > 0) {
      return `播放异常 · ${chapterLabel}`;
    }
    if (snapshot.isLoading) {
      return `正在准备 · ${chapterLabel}`;
    }
    const playbackLabel = snapshot.isPlaying ? '正在播放' : '已暂停';
    return `${chapterLabel} · ${playbackLabel}`;
  }

  private buildNovelAudioProgressSummary(snapshot: NovelAudioReadAloudSnapshot): string {
    const chapterOrder = Math.max(1, snapshot.chapterIndex + 1);
    const totalChapters = Math.max(0, snapshot.totalChapters);
    const chapterText = totalChapters > 0
      ? `第 ${chapterOrder}/${totalChapters} 章`
      : `第 ${chapterOrder} 章`;
    const stateText = snapshot.isLoading ? '准备中' : (snapshot.isPlaying ? '播放中' : '已暂停');
    const cacheText = snapshot.isCachingCurrentChapterAudio
      ? '缓存中'
      : (snapshot.audioChapterCached ? '已缓存' : '未缓存');
    const durationMs = Math.max(0, Math.floor(snapshot.audioDurationMs));
    const positionMs = durationMs > 0
      ? Math.max(0, Math.min(Math.floor(snapshot.audioPositionMs), durationMs))
      : Math.max(0, Math.floor(snapshot.audioPositionMs));
    if (durationMs > 0) {
      const percent = Math.round((positionMs / Math.max(1, durationMs)) * 100);
      return `${percent}% · ${this.formatDurationText(positionMs)} / ${this.formatDurationText(durationMs)} · ${chapterText} · ${cacheText}`;
    }
    return `${chapterText} · ${stateText} · ${cacheText}`;
  }

  private formatDurationText(durationMs: number): string {
    const totalSeconds = Math.max(0, Math.floor(durationMs / 1000));
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;
    if (hours > 0) {
      return `${hours}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
    }
    return `${minutes}:${String(seconds).padStart(2, '0')}`;
  }

  private resolveStatusText(snapshot: ReadAloudStateSnapshot): string {
    const text = (AppStorage.get<string>(READ_ALOUD_UI_STATUS_TEXT_KEY) ?? '').trim();
    const detail = (AppStorage.get<string>(READ_ALOUD_UI_STATUS_DETAIL_KEY) ?? '').trim();
    const fallback = snapshot.playbackState === ReadAloudPlaybackState.PLAYING ? '正在播放' : '已暂停';
    if (text.length > 0 && detail.length > 0) {
      return `${text} · ${detail}`;
    }
    if (text.length > 0) {
      return text;
    }
    if (detail.length > 0) {
      return detail;
    }
    return fallback;
  }

  private buildProgressSummary(snapshot: ReadAloudStateSnapshot, context: ReadAloudSessionContext | null): string {
    const contentLength = Math.max(0, context?.content.length ?? 0);
    const maxCharIndex = Math.max(0, contentLength - 1);
    const rawCharIndex = snapshot.currentCharIndex >= 0
      ? snapshot.currentCharIndex
      : (context?.resumeCharIndex ?? 0);
    const safeCharIndex = contentLength > 0
      ? Math.max(0, Math.min(rawCharIndex, maxCharIndex))
      : -1;
    const percent = this.calculateProgressPercent(snapshot, contentLength, safeCharIndex, maxCharIndex);
    const percentText = `${Math.round(percent)}%`;
    const charText = contentLength > 0 && safeCharIndex >= 0
      ? `第 ${safeCharIndex + 1}/${contentLength} 字`
      : '定位中';
    const stateText = snapshot.playbackState === ReadAloudPlaybackState.PLAYING ? '播放中' : '已暂停';
    if (snapshot.chunkStartCharIndex >= 0 && snapshot.chunkEndCharIndex > snapshot.chunkStartCharIndex) {
      return `${percentText} · ${charText} · ${stateText} · 片段 ${snapshot.chunkStartCharIndex + 1}-${snapshot.chunkEndCharIndex}`;
    }
    return `${percentText} · ${charText} · ${stateText}`;
  }

  private calculateProgressPercent(
    snapshot: ReadAloudStateSnapshot,
    contentLength: number,
    safeCharIndex: number,
    maxCharIndex: number
  ): number {
    if (snapshot.totalDurationMs > 0 && snapshot.currentPositionMs >= 0) {
      const safePositionMs = Math.max(0, Math.min(snapshot.currentPositionMs, snapshot.totalDurationMs));
      return (safePositionMs / Math.max(1, snapshot.totalDurationMs)) * 100;
    }
    if (contentLength <= 1 || safeCharIndex < 0) {
      return 0;
    }
    return (safeCharIndex / Math.max(1, maxCharIndex)) * 100;
  }

  private buildMarqueeText(): string {
    const source = this.marqueeSourceText.trim();
    if (source.length <= 0) {
      return '';
    }
    if (source.length <= FLOATING_BALL_MARQUEE_WINDOW_SIZE) {
      return source;
    }
    const padded = `${source}   `;
    const start = this.marqueeOffset % padded.length;
    const doubled = `${padded}${padded}`;
    return doubled.substring(start, start + FLOATING_BALL_MARQUEE_WINDOW_SIZE);
  }

  private updateMarqueeText(): void {
    if (this.isExitingByLongPress) {
      this.marqueeSourceText = FLOATING_BALL_EXIT_HINT_TEXT;
      this.marqueeOffset = 0;
      this.marqueeText = FLOATING_BALL_EXIT_HINT_TEXT;
      return;
    }
    if (this.marqueeSourceText.length <= FLOATING_BALL_MARQUEE_WINDOW_SIZE) {
      this.marqueeText = this.marqueeSourceText;
      return;
    }
    this.marqueeOffset = (this.marqueeOffset + 1) % (this.marqueeSourceText.length + 3);
    this.marqueeText = this.buildMarqueeText();
  }

  private togglePlayback(): void {
    if (this.isExitingByLongPress) {
      return;
    }
    const novelAudioSnapshot = this.novelAudioSessionManager.getSnapshot();
    if (novelAudioSnapshot.hasSession) {
      void this.toggleNovelAudioPlayback();
      return;
    }
    const snapshot = this.readAloudController.getSnapshot();
    if (!snapshot.hasContext) {
      this.getUIContext().getPromptAction().showToast({
        message: '当前没有可播放内容',
        duration: 1500
      });
      return;
    }
    if (snapshot.playbackState === ReadAloudPlaybackState.PLAYING) {
      this.readAloudController.pause('floating_ball_toggle');
    } else {
      this.readAloudController.start('floating_ball_toggle');
    }
    this.readAloudController.refreshMediaSession();
    this.refreshBallState();
  }

  private async toggleNovelAudioPlayback(): Promise<void> {
    const snapshot = this.novelAudioSessionManager.getSnapshot();
    if (!snapshot.hasSession) {
      this.getUIContext().getPromptAction().showToast({
        message: '当前没有可播放的听书会话',
        duration: 1500
      });
      return;
    }
    try {
      await this.novelAudioSessionManager.togglePlayPause();
    } catch (error) {
      logger.warn(TAG, `悬浮球切换听书播放状态失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({
        message: '切换播放状态失败',
        duration: 1500
      });
    }
    this.refreshBallState();
  }

  private openPlayerPage(): void {
    const novelAudioSnapshot = this.novelAudioSessionManager.getSnapshot();
    const context = this.readAloudController.getContextSnapshot();
    if (!novelAudioSnapshot.hasSession && !context) {
      this.getUIContext().getPromptAction().showToast({
        message: '当前没有可播放内容',
        duration: 1500
      });
      return;
    }

    const currentHostPage = (AppStorage.get<string>('ReadAloudCurrentHostPage') ?? '').trim();
    const isReaderHost = currentHostPage === 'NovelReaderPage' ||
      currentHostPage === 'EBookReaderPage' ||
      currentHostPage === 'EpubWebViewReaderPage';

    let returnHostPage: string = '';
    let returnDisplayMode: DisplayMode | null = null;
    if (isReaderHost) {
      returnHostPage = currentHostPage;
      returnDisplayMode = WindowManager.getCurrentMode();
    }
    AppStorage.setOrCreate('ReadAloudPlayerOpeningAt', Date.now());
    this.showBackRouteIcon = true;
    openReadAloudPlayerInIsolatedAbility(
      this.getUIContext(),
      AppStorage.get<NavPathStack>('GlobalNavStack'),
      TAG,
      returnHostPage,
      returnDisplayMode,
      null
    );
  }

  private returnToReaderPage(): void {
    const globalStack = AppStorage.get<NavPathStack>('GlobalNavStack');
    if (!globalStack) {
      logger.warn(TAG, '无法获取 GlobalNavStack，无法返回阅读器');
      return;
    }
    try {
      if (globalStack.size() <= 0) {
        return;
      }
      const returnHostPage = (AppStorage.get<string>('ReadAloudPlayerReturnHostPage') ?? '').trim();
      if (returnHostPage.length > 0) {
        AppStorage.setOrCreate('ReadAloudCurrentHostPage', returnHostPage);
      }
      this.showBackRouteIcon = false;
      globalStack.pop();
    } catch (error) {
      logger.warn(TAG, `返回阅读器失败: ${String(error)}`);
    }
  }

  private isPlayerHostPage(): boolean {
    const hostPage = AppStorage.get<string>('ReadAloudCurrentHostPage') ?? '';
    return hostPage === 'ReadAloudPlayerPage';
  }

  private handleRouteButtonClick(): void {
    if (this.isExitingByLongPress) {
      return;
    }
    if (this.isPlayerHostPage()) {
      this.returnToReaderPage();
      return;
    }
    this.openPlayerPage();
  }

  private resolveBackgroundColor(): string {
    if (this.isExitingByLongPress) {
      return 'rgba(42,179,96,0.94)';
    }
    if (this.currentPhase === 'error') {
      return 'rgba(186,65,65,0.94)';
    }
    if (
      this.currentPhase === 'requesting' ||
      this.currentPhase === 'retrying' ||
      this.currentPhase === 'preparing' ||
      this.currentPhase === 'buffering'
    ) {
      return 'rgba(219,135,41,0.94)';
    }
    if (this.isPlaying) {
      return 'rgba(24,144,255,0.92)';
    }
    return 'rgba(36,36,40,0.88)';
  }

  build() {
    if (this.isVisible) {
      Row({ space: 8 }) {
        Button() {
          SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
            .fontSize(17)
            .fontColor([Color.White])
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor('rgba(255,255,255,0.15)')
        .onClick(() => this.togglePlayback())

        Column({ space: 2 }) {
          Text(this.marqueeText.length > 0 ? this.marqueeText : (this.isPlaying ? '正在播放' : '已暂停'))
            .fontSize(12)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width(166)
            .textAlign(TextAlign.Start)

          Text(this.progressSummaryText)
            .fontSize(10)
            .fontColor('rgba(255,255,255,0.82)')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width(166)
            .textAlign(TextAlign.Start)
        }
        .alignItems(HorizontalAlign.Start)

        Column()
          .width(1)
          .height(22)
          .backgroundColor('rgba(255,255,255,0.22)')

        Button() {
          SymbolGlyph(this.showBackRouteIcon ? $r('sys.symbol.arrow_left') : $r('sys.symbol.book'))
            .fontSize(15)
            .fontColor([Color.White])
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor('rgba(255,255,255,0.15)')
        .onClick(() => this.handleRouteButtonClick())
      }
      .padding({ left: 8, right: 8, top: 8, bottom: 8 })
      .backgroundColor(this.resolveBackgroundColor())
      .borderRadius(22)
      .border({ width: 1, color: 'rgba(255,255,255,0.16)' })
      .shadow({
        radius: 12,
        color: 'rgba(0,0,0,0.24)',
        offsetX: 0,
        offsetY: 4
      })
      .position({
        x: this.ballX,
        y: this.ballY
      })
      .animation({ duration: 220, curve: Curve.EaseOut })
      .gesture(
        PanGesture()
          .onActionStart((event: GestureEvent) => {
            if (this.isExitingByLongPress) {
              return;
            }
            this.isDragging = false;
            this.dragStartX = event.offsetX;
            this.dragStartY = event.offsetY;
            this.ballStartX = this.ballX;
            this.ballStartY = this.ballY;
          })
          .onActionUpdate((event: GestureEvent) => {
            if (this.isExitingByLongPress) {
              return;
            }
            const deltaX = event.offsetX - this.dragStartX;
            const deltaY = event.offsetY - this.dragStartY;
            if (!this.isDragging) {
              const distance = Math.sqrt((deltaX * deltaX) + (deltaY * deltaY));
              if (distance < FLOATING_BALL_DRAG_START_THRESHOLD_PX) {
                return;
              }
              this.isDragging = true;
              this.hasUserDraggedBall = true;
              this.clearLongPressExitHoldTimer();
            }
            if (!this.isDragging) {
              return;
            }
            this.ballX = this.ballStartX + deltaX;
            this.ballY = this.ballStartY + deltaY;
          })
          .onActionEnd(() => {
            this.isDragging = false;
            this.clearLongPressExitHoldTimer();
          })
      )
      .parallelGesture(
        LongPressGesture({ repeat: false, duration: FLOATING_BALL_LONG_PRESS_EXIT_HOLD_MS })
          .onAction(() => {
            logger.info(TAG, `听书悬浮球识别长按手势: 会话=${this.activeSessionKey}`);
            this.handleLongPressExitTriggered();
          })
      )
      .zIndex(30000)
    }
  }
}
