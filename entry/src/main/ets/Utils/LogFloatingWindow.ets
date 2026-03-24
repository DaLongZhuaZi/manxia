import { ThemeAwareHelper, ThemeAwareState } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { logCollector, LogEntry, LogFilter } from '../Framework/Debug/LogCollector';
import { logger, LogLevel } from './Logger';
import { TimeUtils } from '../Framework/Utils/TimeUtils';
import { UIContext, display } from '@kit.ArkUI';

interface ShadowStyle {
  radius: number;
  color: ResourceStr | string;
  offsetX: number;
  offsetY: number;
}

interface PaddingStyle {
  left?: number;
  right?: number;
  top?: number;
  bottom?: number;
}

@Observed
export class LogFloatingWindowController {
  public visible: boolean = false;
  public open(): void {
    this.visible = true;
  }
  public close(): void {
    this.visible = false;
  }
  public toggle(): void {
    this.visible = !this.visible;
  }
}

@Component
export struct LogFloatingWindow {
  @State visible: boolean = true;
  @State private isMinimized: boolean = true;
  @State private logs: LogEntry[] = [];
  @State private logFilter: LogFilter = {};
  @State private themeState: ThemeAwareState = new ThemeAwareState();
  @State private offsetX: number = 280;
  @State private offsetY: number = 520;
  @State private positionX: number = 280;
  @State private positionY: number = 520;
  @State private startDragX: number = 0;
  @State private startDragY: number = 0;
  @State private ballScale: number = 1;
  @State private expandedLogs: Set<number> = new Set<number>();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  private themeManager: ThemeManager = ThemeManager.getInstance();
  private uiContext: UIContext | undefined = undefined;
  private scroller: Scroller = new Scroller();
  private listenerRef: (entry: LogEntry) => void = (entry: LogEntry) => {};

  aboutToAppear(): void {
    this.uiContext = this.getUIContext();
    const currentTheme: ThemeType = this.themeManager.getActualThemeSync();
    this.themeState.updateTheme(currentTheme);
    this.themeManager.onThemeChange((theme: ThemeType): void => {
      this.themeState.updateTheme(theme);
    });

    try {
      const info = display.getDefaultDisplaySync();
      const density = info.densityDPI / 160;
      const totalVpH = info.height / density;
      const contentVpH = totalVpH - this.statusBarHeight - this.navigationBarHeight;
      const centerY = this.statusBarHeight + (contentVpH > 0 ? (contentVpH / 2) : (totalVpH / 2));
      const leftMargin = 24;
      this.positionX = leftMargin;
      this.offsetX = leftMargin;
      this.positionY = centerY;
      this.offsetY = centerY;
    } catch (e) {
      logger.warn('LogFloatingWindow', '无法获取显示信息，使用默认偏移');
    }
    this.logs = logCollector.getFilteredLogs(this.logFilter);
    this.listenerRef = (entry: LogEntry): void => {
      if (this.matchesFilter(entry)) {
        const next: LogEntry[] = [];
        for (let i = 0; i < this.logs.length; i++) {
          next.push(this.logs[i]);
        }
        next.push(entry);
        this.logs = next;
        setTimeout((): void => { this.scroller.scrollToIndex(this.logs.length - 1); }, 50);
      }
    };
    logCollector.addListener(this.listenerRef);
    logger.info('LogFloatingWindow', '已初始化');
  }

  aboutToDisappear(): void {
    logCollector.removeListener(this.listenerRef);
  }

  private matchesFilter(entry: LogEntry): boolean {
    const filter = this.logFilter;
    if (filter.level !== undefined && entry.level < filter.level) {
      return false;
    }
    if (filter.tag && !entry.tag.toLowerCase().includes(filter.tag.toLowerCase())) {
      return false;
    }
    if (filter.searchText) {
      const s = filter.searchText.toLowerCase();
      const hasMessage = entry.message.toLowerCase().includes(s);
      const hasTag = entry.tag.toLowerCase().includes(s);
      if (!hasMessage && !hasTag) {
        return false;
      }
    }
    if (filter.startTime && entry.timestamp < filter.startTime) {
      return false;
    }
    if (filter.endTime && entry.timestamp > filter.endTime) {
      return false;
    }
    return true;
  }

  private setFilterLevel(level: LogLevel | undefined): void {
    const f: LogFilter = {};
    if (level !== undefined) {
      f.level = level;
    }
    this.logFilter = f;
    this.logs = logCollector.getFilteredLogs(this.logFilter);
    setTimeout((): void => { if (this.logs.length > 0) { this.scroller.scrollToIndex(this.logs.length - 1); } }, 50);
  }

  private getLevelColor(level: LogLevel): Resource {
    const theme = this.themeState.currentTheme;
    if (level === LogLevel.ERROR) {
      return ThemeAwareHelper.getTestManagementThemedColor('color_error', theme);
    }
    if (level === LogLevel.WARN) {
      return ThemeAwareHelper.getTestManagementThemedColor('color_warning', theme);
    }
    if (level === LogLevel.INFO) {
      return ThemeAwareHelper.getTestManagementThemedColor('color_info', theme);
    }
    return ThemeAwareHelper.getTestManagementThemedColor('color_neutral', theme);
  }

  private formatTime(ts: number): string {
    return TimeUtils.formatTimestamp(ts, 'HH:mm:ss.SSS');
  }

  build() {
    if (this.visible) {
      if (this.isMinimized) {
        this.FloatingBall();
      } else {
        Stack() {
          Row() {
            Blank()
              .width('100%')
              .height('100%')
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
              .backgroundColor('rgba(0, 0, 0, 0.35)')
              .onClick(() => { this.isMinimized = true; });
          }
          .width('100%')
          .height('100%');

          Column() {
            this.TitleBar();
            this.FilterBar();
            this.LogList();

          }
          .width('95%')
          .height('85%')
          .padding({ top: this.statusBarHeight, bottom: this.navigationBarHeight } as PaddingStyle)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_dark', this.themeState.currentTheme))
          .borderRadius(12)
          .padding(16)
          .shadow({ radius: 24, color: ThemeAwareHelper.getTestManagementThemedColor('shadow_black', this.themeState.currentTheme), offsetX: 0, offsetY: 4 } as ShadowStyle)
          .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('border_dark', this.themeState.currentTheme) })
          .alignSelf(ItemAlign.Center)
          .justifyContent(FlexAlign.Start)
          .margin({ top: '7.5%' })
          .onClick(() => {})
        }
        .width('100%')
        .height('100%')
        .alignContent(Alignment.Center)
      }
    }
  }

  // 悬浮球
  @Builder FloatingBall() {
    Stack() {
      Button() {
        Column({ space: 2 }) {
          Text('📜').fontSize(20).fontColor($r('app.color.text_primary'));
          Text('Logs').fontSize(8).fontColor($r('app.color.text_primary')).opacity(0.8);
        }
      }
      .width(64)
      .height(64)
      .borderRadius(32)
      .backgroundColor(Color.Transparent)
      .shadow({ radius: 12, color: ThemeAwareHelper.getTestManagementThemedColor('shadow_black', this.themeState.currentTheme), offsetX: 0, offsetY: 2 } as ShadowStyle)
      
    }
    .width(72)
    .height(72)
    .borderRadius(36)
    .backgroundColor(ThemeManager.getInstance().getPopupBlurOptions().backgroundColorResource)
    .backgroundBlurStyle(ThemeManager.getInstance().getPopupBlurOptions().blurStyle)
    .shadow({ radius: ThemeManager.getInstance().getPopupBlurOptions().radius, color: ThemeManager.getInstance().getPopupBlurOptions().shadowColor, offsetX: 0, offsetY: 2 } as ShadowStyle)
    .position({ x: this.offsetX, y: this.offsetY })
    .scale({ x: this.ballScale, y: this.ballScale })
    .onClick(() => { this.isMinimized = false; })
    .gesture(
      PanGesture()
        .onActionStart((event: GestureEvent) => {
          this.startDragX = this.offsetX;
          this.startDragY = this.offsetY;
          const ctx = this.uiContext;
          if (ctx) {
            ctx.animateTo({ duration: 120, curve: Curve.EaseOut }, () => { this.ballScale = 0.96; });
          } else {
            this.ballScale = 0.96;
          }
        })
        .onActionUpdate((event: GestureEvent) => {
          if (event) {
            this.offsetX = this.positionX + event.offsetX;
            this.offsetY = this.positionY + event.offsetY;
          }
        })
        .onActionEnd((event: GestureEvent) => {
          const prevX = this.startDragX;
          const prevY = this.startDragY;
          const curX = this.offsetX;
          const curY = this.offsetY;
          this.positionX = curX;
          this.positionY = curY;
          const dx = curX - prevX;
          const dy = curY - prevY;
          const dist2 = dx * dx + dy * dy;
          const clickThreshold2 = 25;
          if (dist2 <= clickThreshold2) {
            this.isMinimized = false;
          }
          const ctx = this.uiContext;
          if (ctx) {
            ctx.animateTo({ duration: 220, curve: Curve.Friction }, () => { this.ballScale = 1; this.offsetX = this.positionX; this.offsetY = this.positionY; });
          } else {
            this.ballScale = 1;
          }
        })
    )
    .hitTestBehavior(HitTestMode.Block);
  }

  // 标题栏
  @Builder TitleBar() {
    Row() {
      Row({ space: 8 }) {
        Text('🧾').fontSize(20);
        Text('日志窗口')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme));
      }
      Blank();
      Row({ space: 8 }) {
        Button('—')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .width(32)
          .height(32)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_secondary', this.themeState.currentTheme))
          .borderRadius(6)
          .onClick(() => { this.isMinimized = true; });
        Button('✕')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .width(32)
          .height(32)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
          .borderRadius(6)
          .onClick(() => { this.visible = false; });
      }
    }
    .width('100%')
    .height(48)
    .padding({ bottom: 12 })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center);
  }

  // 过滤栏
  @Builder FilterBar() {
    Row({ space: 8 }) {
      Button('全部')
        .fontSize(12)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_secondary', this.themeState.currentTheme))
        .borderRadius(6)
        .onClick(() => { this.setFilterLevel(undefined); });
      Button('信息')
        .fontSize(12)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_info', this.themeState.currentTheme))
        .borderRadius(6)
        .onClick(() => { this.setFilterLevel(LogLevel.INFO); });
      Button('警告')
        .fontSize(12)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_warning', this.themeState.currentTheme))
        .borderRadius(6)
        .onClick(() => { this.setFilterLevel(LogLevel.WARN); });
      Button('错误')
        .fontSize(12)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
        .borderRadius(6)
        .onClick(() => { this.setFilterLevel(LogLevel.ERROR); });
      Blank();
      Button('清空')
        .fontSize(12)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_secondary', this.themeState.currentTheme))
        .borderRadius(6)
        .onClick(() => { logCollector.clearLogs(); this.logs = []; });
    }
    .width('100%')
    .height(40)
    .padding({ bottom: 12 })
    .justifyContent(FlexAlign.SpaceBetween);
  }

  // 日志列表
  @Builder LogList() {
    List({ scroller: this.scroller, space: 2 }) {
      ForEach(this.logs, (item: LogEntry) => {
        ListItem() { this.LogRow(item); }
      }, (item: LogEntry) => item.id.toString());
    }
    .width('100%')
    .height('85%')
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(8)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('border_light', this.themeState.currentTheme) })
    .edgeEffect(EdgeEffect.None);
  }

  // 日志行
  @Builder LogRow(entry: LogEntry) {
    Row({ space: 8 }) {
      Text(this.getDisplayTime(entry))
        .fontSize(10)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme));
      Text(this.getDisplayTag(entry))
        .fontSize(12)
        .fontColor(this.getLevelColor(entry.level))
        .fontWeight(FontWeight.Bold);
      Text(entry.message)
        .fontSize(12)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .layoutWeight(1);
    }
    .width('100%')
    .height(60)
    .padding({ left: 12, right: 12 } as PaddingStyle)
    .justifyContent(FlexAlign.Start)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('row_even', this.themeState.currentTheme))
    .onClick(() => { const id = entry.id; if (this.expandedLogs.has(id)) { this.expandedLogs.delete(id); } else { this.expandedLogs.add(id); } });
  }

  private getDisplayTime(entry: LogEntry): string {
    const idValue: number = entry.id;
    const expanded: boolean = this.expandedLogs.has(idValue);
    if (expanded) {
      return this.formatTime(entry.timestamp);
    }
    const ms: number = entry.timestamp % 1000;
    return `${ms}ms`;
  }

  private getDisplayTag(entry: LogEntry): string {
    const idValue: number = entry.id;
    const expanded: boolean = this.expandedLogs.has(idValue);
    if (expanded) {
      return entry.tag;
    }
    const len: number = entry.tag.length;
    const subLen: number = len < 4 ? len : 4;
    return entry.tag.substring(0, subLen);
  }

}
