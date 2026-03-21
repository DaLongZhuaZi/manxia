import { promptAction, LengthMetrics } from '@kit.ArkUI';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { logger } from '../Utils/Logger';
import { ReadAloudController } from '../Framework/ReadAloud/ReadAloudController';
import { eventBus, GameEvent, IEventPayload } from '../Framework/EventBus';
import { ReadAloudPlaybackState, ReadAloudSessionContext, ReadAloudStateSnapshot } from '../Framework/ReadAloud/ReadAloudTypes';
import { WindowManager, DisplayMode } from '../Utils/WindowManager';
import { ThemeAwareHelper, ThemeAwareState } from '../Framework/Components/ThemeAware';
import { ThemeManager } from '../Framework/Managers/ThemeManager';

const TAG = 'ReadAloudPlayerPage';
const PLAYER_SKIP_CHARS: number = 420;
const PLAYER_TOP_CONTENT_PADDING: number = 8;
const PLAYER_DISPLAY_RESTORE_DELAY_MS: number = 140;
const READ_ALOUD_UI_STATUS_TEXT_KEY = 'ReadAloudUiStatusText';
const READ_ALOUD_UI_STATUS_DETAIL_KEY = 'ReadAloudUiStatusDetail';

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
  @State progressText: string = '0%';
  @State statusText: string = '未播放';
  @State chapterInfoText: string = '--';
  @State pageInfoText: string = '--';
  @State charInfoText: string = '--';
  @State chunkInfoText: string = '--';
  @State engineInfoText: string = '--';
  @State speedInfoText: string = '--';
  @State excerptText: string = '';
  @State entered: boolean = false;

  // 主题状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = `PrivacyPolicyPage_${Date.now()}`;

  private readAloudController: ReadAloudController = ReadAloudController.getInstance();
  private previousDisplayMode: DisplayMode = DisplayMode.DEFAULT;
  private returnHostPage: string = '';
  private hasCapturedRouteState: boolean = false;
  private displayRestoreTimer: number = -1;
  private uiContext: UIContext | null = null;

  private onReadAloudStateChanged: (payload: IEventPayload) => void = (_payload: IEventPayload): void => {
    this.refreshPlayerState();
  };

  aboutToAppear(): void {
    this.captureRouteState('aboutToAppear');
    this.applyPreferredDisplayMode('aboutToAppear');
    AppStorage.setOrCreate('ReadAloudCurrentHostPage', 'ReadAloudPlayerPage');
    eventBus.subscribe(GameEvent.READ_ALOUD_STATE_CHANGED, this.onReadAloudStateChanged);
    this.refreshPlayerState();
    this.readAloudController.refreshMediaSession();
  }

  aboutToDisappear(): void {
    this.clearDisplayRestoreTimer();
    this.restorePreviousDisplayMode('aboutToDisappear');
    const currentHostPage = (AppStorage.get<string>('ReadAloudCurrentHostPage') ?? '').trim();
    if (this.returnHostPage.length > 0) {
      AppStorage.setOrCreate('ReadAloudCurrentHostPage', this.returnHostPage);
    } else if (currentHostPage === 'ReadAloudPlayerPage') {
      AppStorage.setOrCreate('ReadAloudCurrentHostPage', '');
    }
    this.clearPlayerReturnMarkers();
    eventBus.unsubscribe(GameEvent.READ_ALOUD_STATE_CHANGED, this.onReadAloudStateChanged);
  }

  onPageShow(): void {
    this.applyPreferredDisplayMode('onPageShow');
    this.scheduleDisplayRestore('onPageShow');
    AppStorage.setOrCreate('ReadAloudCurrentHostPage', 'ReadAloudPlayerPage');
  }

  onPageHide(): void {
    this.clearDisplayRestoreTimer();
  }

  private ensureUiContext(): UIContext | null {
    if (!this.uiContext) {
      this.uiContext = this.getUIContext();
    }
    return this.uiContext;
  }

  private resolveStoredDisplayMode(): DisplayMode {
    const storedMode = (AppStorage.get<string>('ReadAloudPlayerReturnDisplayMode') ?? '').trim();
    if (storedMode === DisplayMode.FULL_IMMERSIVE) {
      return DisplayMode.FULL_IMMERSIVE;
    }
    if (storedMode === DisplayMode.DEFAULT) {
      return DisplayMode.DEFAULT;
    }
    return WindowManager.getCurrentMode();
  }

  private captureRouteState(trigger: string): void {
    if (this.hasCapturedRouteState) {
      return;
    }
    this.ensureUiContext();
    this.previousDisplayMode = this.resolveStoredDisplayMode();
    this.returnHostPage = (AppStorage.get<string>('ReadAloudPlayerReturnHostPage') ?? '').trim();
    this.hasCapturedRouteState = true;
    logger.info(
      TAG,
      `捕获听书独立页返回上下文: trigger=${trigger}, previousDisplayMode=${this.previousDisplayMode}, returnHostPage=${this.returnHostPage || 'none'}`
    );
  }

  private shouldUseImmersiveMode(): boolean {
    return this.previousDisplayMode === DisplayMode.FULL_IMMERSIVE;
  }

  private applyPreferredDisplayMode(trigger: string): void {
    const context = this.ensureUiContext();
    if (!context) {
      logger.warn(TAG, `应用听书页显示模式失败: trigger=${trigger}, UIContext is null`);
      return;
    }
    const targetMode = this.shouldUseImmersiveMode() ? DisplayMode.FULL_IMMERSIVE : DisplayMode.DEFAULT;
    const currentMode = WindowManager.getCurrentMode();
    if (currentMode === targetMode) {
      logger.debug(TAG, `听书独立页显示模式无需切换: trigger=${trigger}, mode=${targetMode}`);
      return;
    }
    WindowManager.setDisplayMode(targetMode, context);
    logger.info(TAG, `应用听书独立页显示模式: trigger=${trigger}, mode=${targetMode}`);
  }

  private restorePreviousDisplayMode(trigger: string): void {
    const context = this.ensureUiContext();
    if (!context) {
      logger.warn(TAG, `恢复听书页来源显示模式失败: trigger=${trigger}, UIContext is null`);
      return;
    }
    const currentMode = WindowManager.getCurrentMode();
    if (currentMode === this.previousDisplayMode) {
      logger.debug(TAG, `听书页来源显示模式无需恢复: trigger=${trigger}, mode=${this.previousDisplayMode}`);
      return;
    }
    WindowManager.setDisplayMode(this.previousDisplayMode, context);
    logger.info(TAG, `恢复听书页来源显示模式: trigger=${trigger}, mode=${this.previousDisplayMode}`);
  }

  private clearDisplayRestoreTimer(): void {
    if (this.displayRestoreTimer >= 0) {
      clearTimeout(this.displayRestoreTimer);
      this.displayRestoreTimer = -1;
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
      logger.warn(TAG, `返回阅读器前恢复沉浸失败: trigger=${trigger}, UIContext is null`);
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
    logger.info(TAG, `返回阅读器前强制恢复沉浸: trigger=${trigger}`);
  }

  private clearPlayerReturnMarkers(): void {
    AppStorage.setOrCreate('ReadAloudPlayerOpeningAt', 0);
    AppStorage.setOrCreate('ReadAloudPlayerReturnHostPage', '');
    AppStorage.setOrCreate('ReadAloudPlayerReturnDisplayMode', '');
  }

  private refreshPlayerState(): void {
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
      this.chapterInfoText = '--';
      this.pageInfoText = '--';
      this.charInfoText = '--';
      this.chunkInfoText = '--';
      this.engineInfoText = '--';
      this.speedInfoText = '--';
      this.excerptText = '';
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
    if (!this.hasSession) {
      promptAction.showToast({
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

  private skipPrevious(): void {
    if (!this.hasSession) {
      return;
    }
    this.readAloudController.seekByChars(-PLAYER_SKIP_CHARS, 'player_skip_previous');
    this.readAloudController.refreshMediaSession();
    this.refreshPlayerState();
  }

  private skipNext(): void {
    if (!this.hasSession) {
      return;
    }
    this.readAloudController.seekByChars(PLAYER_SKIP_CHARS, 'player_skip_next');
    this.readAloudController.refreshMediaSession();
    this.refreshPlayerState();
  }

  private stopPlayback(): void {
    if (!this.hasSession) {
      return;
    }
    this.readAloudController.stop('player_stop');
    this.readAloudController.refreshMediaSession();
    this.refreshPlayerState();
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
      this.pathStack.pop();
    } catch (error) {
      logger.warn(TAG, `返回失败: ${String(error)}`);
    }
  }

  @Builder
  private buildCoverCard(): void {
    Column({ space: 12 }) {
      if (this.coverUrl.length > 0) {
        Image(this.coverUrl)
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
  private buildProgressCard(): void {
    Column({ space: 10 }) {
      Row() {
        Text('播放进度')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.progressText)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')

      Progress({
        value: this.progressPercent,
        total: 100,
        type: ProgressType.Linear
      })
        .width('100%')
        .height(8)
        .color($r('app.color.accent_primary'))
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.background_secondary'))
    .borderRadius(16)
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
        .onClick(() => this.skipPrevious())

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
        .onClick(() => this.togglePlayPause())

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
        .onClick(() => this.skipNext())
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
        .onClick(() => this.stopPlayback())
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
            this.buildSessionInfoCard()
            this.buildExcerptCard()
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
      this.refreshPlayerState();
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
      this.refreshPlayerState();
      this.readAloudController.refreshMediaSession();
    })
    .onBackPressed(() => {
      this.closePage();
      return true;
    })
  }
}
