import { promptAction } from '@kit.ArkUI';
import { logger } from '../../Utils/Logger';
import { ReadAloudController } from '../ReadAloud/ReadAloudController';
import { eventBus, GameEvent, IEventPayload } from '../EventBus';
import { ReadAloudPlaybackState, ReadAloudSessionContext, ReadAloudStateSnapshot } from '../ReadAloud/ReadAloudTypes';
import { DisplayMode } from '../../Utils/WindowManager';

const TAG = 'ReadAloudFloatingBall';
const FLOATING_BALL_REFRESH_INTERVAL_MS: number = 400;
const FLOATING_BALL_MARQUEE_INTERVAL_MS: number = 220;
const FLOATING_BALL_MARQUEE_WINDOW_SIZE: number = 18;
const READ_ALOUD_UI_STATUS_TEXT_KEY = 'ReadAloudUiStatusText';
const READ_ALOUD_UI_STATUS_DETAIL_KEY = 'ReadAloudUiStatusDetail';
const READ_ALOUD_UI_STATUS_PHASE_KEY = 'ReadAloudUiStatusPhase';

@Component
export struct ReadAloudFloatingBall {
  @State private isVisible: boolean = false;
  @State private isPlaying: boolean = false;
  @State private showBackRouteIcon: boolean = false;
  @State private ballX: number = 20;
  @State private ballY: number = 280;
  @State private isDragging: boolean = false;
  @State private marqueeText: string = '';
  @State private progressSummaryText: string = '';
  @State private currentPhase: string = '';

  private readAloudController: ReadAloudController = ReadAloudController.getInstance();
  private dragStartX: number = 0;
  private dragStartY: number = 0;
  private ballStartX: number = 0;
  private ballStartY: number = 0;
  private stateRefreshTimer: number = -1;
  private marqueeTimer: number = -1;
  private marqueeSourceText: string = '';
  private marqueeOffset: number = 0;

  private onReadAloudStateChanged: (_payload: IEventPayload) => void = (): void => {
    this.refreshBallState();
  };

  aboutToAppear(): void {
    eventBus.subscribe(GameEvent.READ_ALOUD_STATE_CHANGED, this.onReadAloudStateChanged);
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
    if (this.stateRefreshTimer >= 0) {
      clearInterval(this.stateRefreshTimer);
      this.stateRefreshTimer = -1;
    }
    if (this.marqueeTimer >= 0) {
      clearInterval(this.marqueeTimer);
      this.marqueeTimer = -1;
    }
  }

  private refreshBallState(): void {
    const snapshot = this.readAloudController.getSnapshot();
    const context = this.readAloudController.getContextSnapshot();
    const hasValidContext = snapshot.hasContext && context !== null;
    const hasActivePlayback = snapshot.playbackState === ReadAloudPlaybackState.PLAYING ||
      snapshot.playbackState === ReadAloudPlaybackState.PAUSED;
    this.isVisible = hasValidContext && hasActivePlayback;
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
    if (this.marqueeSourceText.length <= FLOATING_BALL_MARQUEE_WINDOW_SIZE) {
      this.marqueeText = this.marqueeSourceText;
      return;
    }
    this.marqueeOffset = (this.marqueeOffset + 1) % (this.marqueeSourceText.length + 3);
    this.marqueeText = this.buildMarqueeText();
  }

  private togglePlayback(): void {
    const snapshot = this.readAloudController.getSnapshot();
    if (!snapshot.hasContext) {
      promptAction.showToast({
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

  private openPlayerPage(): void {
    const context = this.readAloudController.getContextSnapshot();
    if (!context) {
      promptAction.showToast({
        message: '当前没有可播放内容',
        duration: 1500
      });
      return;
    }

    const globalStack = AppStorage.get<NavPathStack>('GlobalNavStack');
    if (!globalStack) {
      logger.warn(TAG, '无法获取 GlobalNavStack，无法打开听书播放页');
      return;
    }

    const currentHostPage = (AppStorage.get<string>('ReadAloudCurrentHostPage') ?? '').trim();
    const isReaderHost = currentHostPage === 'NovelReaderPage' || currentHostPage === 'EBookReaderPage';

    if (isReaderHost) {
      AppStorage.setOrCreate('ReadAloudPlayerReturnHostPage', currentHostPage);
      AppStorage.setOrCreate('ReadAloudPlayerReturnDisplayMode', DisplayMode.FULL_IMMERSIVE);
    } else {
      AppStorage.setOrCreate('ReadAloudPlayerReturnHostPage', '');
      AppStorage.setOrCreate('ReadAloudPlayerReturnDisplayMode', '');
    }
    AppStorage.setOrCreate('ReadAloudPlayerOpeningAt', Date.now());
    this.showBackRouteIcon = true;
    globalStack.pushPathByName('ReadAloudPlayerPage', undefined);
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
    if (this.isPlayerHostPage()) {
      this.returnToReaderPage();
      return;
    }
    this.openPlayerPage();
  }

  private resolveBackgroundColor(): string {
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
          SymbolGlyph(this.showBackRouteIcon ? $r('sys.symbol.chevron_left') : $r('sys.symbol.book'))
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
            this.isDragging = true;
            this.dragStartX = event.offsetX;
            this.dragStartY = event.offsetY;
            this.ballStartX = this.ballX;
            this.ballStartY = this.ballY;
          })
          .onActionUpdate((event: GestureEvent) => {
            if (!this.isDragging) {
              return;
            }
            this.ballX = this.ballStartX + event.offsetX - this.dragStartX;
            this.ballY = this.ballStartY + event.offsetY - this.dragStartY;
          })
          .onActionEnd(() => {
            this.isDragging = false;
          })
      )
      .zIndex(30000)
    }
  }
}
