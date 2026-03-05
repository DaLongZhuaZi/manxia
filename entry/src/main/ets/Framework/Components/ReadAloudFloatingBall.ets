import { promptAction } from '@kit.ArkUI';
import { logger } from '../../Utils/Logger';
import { ReadAloudController } from '../ReadAloud/ReadAloudController';
import { eventBus, GameEvent, IEventPayload } from '../EventBus';
import { ReadAloudPlaybackState } from '../ReadAloud/ReadAloudTypes';

const TAG = 'ReadAloudFloatingBall';
const FLOATING_BALL_REFRESH_INTERVAL_MS: number = 1200;

@Component
export struct ReadAloudFloatingBall {
  @State private isVisible: boolean = false;
  @State private isPlaying: boolean = false;
  @State private showBackRouteIcon: boolean = false;
  @State private ballX: number = 20;
  @State private ballY: number = 280;
  @State private isDragging: boolean = false;

  private readAloudController: ReadAloudController = ReadAloudController.getInstance();
  private dragStartX: number = 0;
  private dragStartY: number = 0;
  private ballStartX: number = 0;
  private ballStartY: number = 0;
  private stateRefreshTimer: number = -1;

  private onReadAloudStateChanged: (payload: IEventPayload) => void = (_payload: IEventPayload): void => {
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
  }

  aboutToDisappear(): void {
    eventBus.unsubscribe(GameEvent.READ_ALOUD_STATE_CHANGED, this.onReadAloudStateChanged);
    if (this.stateRefreshTimer >= 0) {
      clearInterval(this.stateRefreshTimer);
      this.stateRefreshTimer = -1;
    }
  }

  private refreshBallState(): void {
    const snapshot = this.readAloudController.getSnapshot();
    const hasValidContext = snapshot.hasContext;
    const hasActivePlayback = snapshot.playbackState === ReadAloudPlaybackState.PLAYING ||
      snapshot.playbackState === ReadAloudPlaybackState.PAUSED;
    this.isVisible = hasValidContext && hasActivePlayback;
    this.isPlaying = snapshot.playbackState === ReadAloudPlaybackState.PLAYING;
    this.showBackRouteIcon = this.isPlayerHostPage();
  }

  private togglePlayback(): void {
    const snapshot = this.readAloudController.getSnapshot();
    const hasValidContext = snapshot.hasContext;
    if (!hasValidContext) {
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
      logger.warn(TAG, '无法获取 GlobalNavStack，无法打开听书播放器');
      return;
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
      AppStorage.setOrCreate('ReadAloudCurrentHostPage', 'NovelReaderPage');
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

  build() {
    if (this.isVisible) {
      Row({ space: 6 }) {
        Button() {
          SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
            .fontSize(17)
            .fontColor([Color.White])
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor($r('app.color.accent_primary'))
        .onClick(() => this.togglePlayback())

        Column()
          .width(1)
          .height(16)
          .backgroundColor('rgba(255,255,255,0.28)')

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
      .padding({ left: 8, right: 8, top: 7, bottom: 7 })
      .backgroundColor(this.isPlaying ? 'rgba(24,144,255,0.92)' : 'rgba(36,36,40,0.86)')
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
