import { logger } from '../Utils/Logger';
import {
  DoublePagePortraitLayout,
  DoublePageVerticalDirection,
  ReadingDirection,
  ReadingMode
} from '../Models/MangaModels';

const TAG = 'MangaInteractionOverlay';
const OVERLAY_FADE_IN_DELAY_MS: number = 50;

export enum InteractionZoneType {
  PAGE_TURN_PREV = 'PAGE_TURN_PREV',
  PAGE_TURN_NEXT = 'PAGE_TURN_NEXT',
  TOOLBAR_TOGGLE = 'TOOLBAR_TOGGLE'
}

export interface InteractionZone {
  type: InteractionZoneType;
  left: number;
  top: number;
  width: number;
  height: number;
  label: string;
}

export interface MangaInteractionOverlayParams {
  readingMode: ReadingMode;
  readingDirection: ReadingDirection;
  doublePagePortraitLayout?: DoublePagePortraitLayout;
  doublePageVerticalDirection?: DoublePageVerticalDirection;
  componentWidth: number;
  componentHeight: number;
  deviceOrientation: 'portrait' | 'landscape' | 'square';
  modeLocked?: boolean;
  orientationLocked?: boolean;
  singlePageAutoDoublePageAvailable?: boolean;
  landscapeAutoDoublePageActive?: boolean;
  statusBarHeight: number;
  navigationBarHeight: number;
  onDismiss: () => void;
}

interface ColorScheme {
  background: string;
  border: string;
  text: string;
}

@Component
export struct MangaInteractionOverlay {
  @Prop params: MangaInteractionOverlayParams;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State private zones: InteractionZone[] = [];
  @State private overlayOpacity: number = 0;

  aboutToAppear(): void {
    this.zones = this.buildZones();
    setTimeout(() => {
      this.overlayOpacity = 1;
    }, OVERLAY_FADE_IN_DELAY_MS);
    logger.info(
      TAG,
      `overlay ready: mode=${this.params.readingMode}, direction=${this.params.readingDirection}, zones=${this.zones.length}`
    );
  }

  private isContinuousMode(): boolean {
    return this.params.readingMode === ReadingMode.WEBTOON ||
      this.params.readingMode === ReadingMode.WEBTOON_WITH_GAP ||
      this.params.readingMode === ReadingMode.CONTINUOUS_VERTICAL;
  }

  private isVerticalPagingMode(): boolean {
    if (this.params.readingMode === ReadingMode.SINGLE_PAGE_TTB) {
      return true;
    }
    if (this.isDoublePageVerticalLayoutMode()) {
      return true;
    }
    return (
      this.params.readingMode === ReadingMode.SINGLE_PAGE ||
      this.params.readingMode === ReadingMode.DOUBLE_PAGE
    ) && (
      this.params.readingDirection === ReadingDirection.TOP_TO_BOTTOM ||
      this.params.readingDirection === ReadingDirection.VERTICAL
    );
  }

  private isRtlPagingMode(): boolean {
    if (this.params.readingMode === ReadingMode.SINGLE_PAGE_RTL) {
      return true;
    }
    return this.params.readingDirection === ReadingDirection.RIGHT_TO_LEFT;
  }

  private isDoublePageVerticalLayoutMode(): boolean {
    return this.params.readingMode === ReadingMode.DOUBLE_PAGE &&
      this.params.deviceOrientation === 'portrait' &&
      (this.params.doublePagePortraitLayout ?? DoublePagePortraitLayout.VERTICAL) === DoublePagePortraitLayout.VERTICAL;
  }

  private isDoublePageVerticalNextAtTop(): boolean {
    return (this.params.doublePageVerticalDirection ?? DoublePageVerticalDirection.TOP_TO_BOTTOM) ===
      DoublePageVerticalDirection.BOTTOM_TO_TOP;
  }

  private buildZones(): InteractionZone[] {
    const width = Math.max(1, this.params.componentWidth);
    const height = Math.max(1, this.params.componentHeight);

    if (this.isContinuousMode()) {
      return [{
        type: InteractionZoneType.TOOLBAR_TOGGLE,
        left: 0,
        top: 0,
        width,
        height,
        label: '单击任意位置\n显示或隐藏工具栏'
      }];
    }

    if (this.isDoublePageVerticalLayoutMode()) {
      return [{
        type: InteractionZoneType.TOOLBAR_TOGGLE,
        left: 0,
        top: 0,
        width,
        height,
        label: '单击任意位置\n显示或隐藏工具栏'
      }];
    }

    if (this.params.readingMode === ReadingMode.DOUBLE_PAGE) {
      if (this.isVerticalPagingMode()) {
        return this.buildVerticalZones(width, height, false, this.isDoublePageVerticalNextAtTop());
      }
      return this.buildDoublePageZones(width, height, this.isRtlPagingMode());
    }

    if (this.isVerticalPagingMode()) {
      return this.buildVerticalZones(width, height, true, false);
    }

    return this.buildHorizontalZones(width, height, this.isRtlPagingMode());
  }

  private buildHorizontalZones(width: number, height: number, isRtl: boolean): InteractionZone[] {
    const sideWidth = width * 0.3;
    const middleWidth = width - sideWidth * 2;
    return [
      {
        type: isRtl ? InteractionZoneType.PAGE_TURN_NEXT : InteractionZoneType.PAGE_TURN_PREV,
        left: 0,
        top: 0,
        width: sideWidth,
        height,
        label: isRtl ? '下一页' : '上一页'
      },
      {
        type: InteractionZoneType.TOOLBAR_TOGGLE,
        left: sideWidth,
        top: 0,
        width: middleWidth,
        height,
        label: '显示/隐藏\n工具栏'
      },
      {
        type: isRtl ? InteractionZoneType.PAGE_TURN_PREV : InteractionZoneType.PAGE_TURN_NEXT,
        left: sideWidth + middleWidth,
        top: 0,
        width: sideWidth,
        height,
        label: isRtl ? '上一页' : '下一页'
      }
    ];
  }

  private buildVerticalZones(
    width: number,
    height: number,
    isSinglePage: boolean,
    nextAtTop: boolean
  ): InteractionZone[] {
    const sideHeight = height * 0.3;
    const middleHeight = height - sideHeight * 2;
    const toolbarLabel = isSinglePage ? '显示/隐藏\n工具栏' : '双页中部\n显示工具栏';
    return [
      {
        type: nextAtTop ? InteractionZoneType.PAGE_TURN_NEXT : InteractionZoneType.PAGE_TURN_PREV,
        left: 0,
        top: 0,
        width,
        height: sideHeight,
        label: nextAtTop ? '下一页' : '上一页'
      },
      {
        type: InteractionZoneType.TOOLBAR_TOGGLE,
        left: 0,
        top: sideHeight,
        width,
        height: middleHeight,
        label: toolbarLabel
      },
      {
        type: nextAtTop ? InteractionZoneType.PAGE_TURN_PREV : InteractionZoneType.PAGE_TURN_NEXT,
        left: 0,
        top: sideHeight + middleHeight,
        width,
        height: sideHeight,
        label: nextAtTop ? '上一页' : '下一页'
      }
    ];
  }

  private buildDoublePageZones(width: number, height: number, isRtl: boolean): InteractionZone[] {
    const edgeWidth = width / 6;
    const middleWidth = width - edgeWidth * 2;
    return [
      {
        type: isRtl ? InteractionZoneType.PAGE_TURN_NEXT : InteractionZoneType.PAGE_TURN_PREV,
        left: 0,
        top: 0,
        width: edgeWidth,
        height,
        label: isRtl ? '下一页' : '上一页'
      },
      {
        type: InteractionZoneType.TOOLBAR_TOGGLE,
        left: edgeWidth,
        top: 0,
        width: middleWidth,
        height,
        label: '中间大区域\n显示工具栏'
      },
      {
        type: isRtl ? InteractionZoneType.PAGE_TURN_PREV : InteractionZoneType.PAGE_TURN_NEXT,
        left: edgeWidth + middleWidth,
        top: 0,
        width: edgeWidth,
        height,
        label: isRtl ? '上一页' : '下一页'
      }
    ];
  }

  private getColorScheme(type: InteractionZoneType): ColorScheme {
    switch (type) {
      case InteractionZoneType.PAGE_TURN_PREV:
        return {
          background: 'rgba(33, 150, 243, 0.18)',
          border: 'rgba(33, 150, 243, 0.78)',
          text: 'rgba(127, 206, 255, 1)'
        };
      case InteractionZoneType.PAGE_TURN_NEXT:
        return {
          background: 'rgba(76, 175, 80, 0.18)',
          border: 'rgba(76, 175, 80, 0.78)',
          text: 'rgba(156, 255, 178, 1)'
        };
      case InteractionZoneType.TOOLBAR_TOGGLE:
      default:
        return {
          background: 'rgba(255, 152, 0, 0.18)',
          border: 'rgba(255, 152, 0, 0.82)',
          text: 'rgba(255, 216, 133, 1)'
        };
    }
  }

  private getModeDescription(): string {
    if (this.isContinuousMode()) {
      switch (this.params.readingMode) {
        case ReadingMode.WEBTOON:
          return '条漫模式：上下滚动阅读，单击任意位置显示或隐藏工具栏。';
        case ReadingMode.WEBTOON_WITH_GAP:
          return '条漫留白模式：上下滚动阅读，保留页间留白，单击任意位置显示或隐藏工具栏。';
        default:
          return '连续滚动模式：上下无缝滚动阅读，单击任意位置显示或隐藏工具栏。';
      }
    }

    if (this.params.readingMode === ReadingMode.DOUBLE_PAGE) {
      if (this.isDoublePageVerticalLayoutMode()) {
        return this.isDoublePageVerticalNextAtTop()
          ? '双页纵向模式（下到上）：继续上推触顶进入下一对页，回拉至触底返回上一对页；单击任意位置显示或隐藏工具栏。'
          : '双页纵向模式（上到下）：继续下拉触底进入下一对页，回推至触顶返回上一对页；单击任意位置显示或隐藏工具栏。';
      }
      return this.isRtlPagingMode()
        ? '双页模式（从右往左）：左侧窄边缘下一页，中间大区域显示工具栏，右侧窄边缘上一页。'
        : '双页模式（从左往右）：左侧窄边缘上一页，中间大区域显示工具栏，右侧窄边缘下一页。';
    }

    if (this.isVerticalPagingMode()) {
      return '单页纵向模式：上方上一页，中间显示工具栏，下方下一页。';
    }

    return this.isRtlPagingMode()
      ? '单页横向模式（从右往左）：左侧下一页，中间显示工具栏，右侧上一页。'
      : '单页横向模式（从左往右）：左侧上一页，中间显示工具栏，右侧下一页。';
  }

  private getReminderText(): string {
    if (this.isContinuousMode()) {
      return '提示：连续滚动模式没有左右翻页热区，工具栏通过单击任意位置呼出。';
    }
    if (this.params.readingMode === ReadingMode.DOUBLE_PAGE) {
      if (this.isDoublePageVerticalLayoutMode()) {
        return this.isDoublePageVerticalNextAtTop()
          ? '提示：当前为上下双页，下方到上方阅读；自然滚动触顶进入下一对页、触底返回上一对页，点击仅显示或隐藏工具栏。'
          : '提示：当前为上下双页，上方到下方阅读；自然滚动触底进入下一对页、触顶返回上一对页，点击仅显示或隐藏工具栏。';
      }
      return '提示：双页模式只有左右边缘翻页，中间的大区域负责显示或隐藏工具栏；横向跨页和比例异常页会自动切换为单显。';
    }
    return '提示：点击任意标记区域都可以快速确认当前翻页方向。';
  }

  private getOrientationReminderText(): string {
    if (this.params.landscapeAutoDoublePageActive ?? false) {
      return '模式未锁定：当前由单页模式临时切换为左右双页，转回竖屏会恢复单页。';
    }
    if (this.params.singlePageAutoDoublePageAvailable ?? false) {
      return '模式未锁定：单页模式下旋转到横屏会临时切换为左右双页。';
    }
    if ((this.params.modeLocked ?? this.params.orientationLocked) ?? false) {
      return '模式已锁定：旋转设备时会保持当前阅读模式。';
    }
    return '';
  }

  private getLegendText(type: InteractionZoneType): string {
    switch (type) {
      case InteractionZoneType.PAGE_TURN_PREV:
        return '蓝色区域：翻到上一页';
      case InteractionZoneType.PAGE_TURN_NEXT:
        return '绿色区域：翻到下一页';
      case InteractionZoneType.TOOLBAR_TOGGLE:
      default:
        return this.isContinuousMode() || this.isDoublePageVerticalLayoutMode()
          ? '橙色区域：单击任意位置显示或隐藏工具栏'
          : '橙色区域：显示或隐藏工具栏';
    }
  }

  private hasZoneType(type: InteractionZoneType): boolean {
    return this.zones.some((zone: InteractionZone) => zone.type === type);
  }

  @Builder
  private buildZone(zone: InteractionZone): void {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.getColorScheme(zone.type).background)

      Column()
        .width('100%')
        .height('100%')
        .border({
          width: 3,
          color: this.getColorScheme(zone.type).border,
          style: BorderStyle.Dashed
        })

      Column({ space: 8 }) {
        Text(zone.label)
          .fontSize(this.isContinuousMode() ? 24 : 18)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getColorScheme(zone.type).text)
          .textAlign(TextAlign.Center)
          .textShadow({
            radius: 4,
            color: 'rgba(0, 0, 0, 0.45)',
            offsetX: 0,
            offsetY: 2
          })
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .padding(12)
    }
    .width(zone.width)
    .height(zone.height)
    .position({ x: zone.left, y: zone.top })
  }

  @Builder
  private buildLegendRow(type: InteractionZoneType): void {
    Row({ space: 8 }) {
      Text('●')
        .fontSize(14)
        .fontColor(this.getColorScheme(type).text)
        .fontFamily(this.appFontFamily)
      Text(this.getLegendText(type))
        .fontSize(14)
        .fontColor(this.getColorScheme(type).text)
        .fontFamily(this.appFontFamily)
        .layoutWeight(1)
    }
    .width('100%')
  }

  @Builder
  private buildInstructionPanel(): void {
    Column({ space: 12 }) {
      Text('阅读手势说明')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .fontFamily(this.appFontFamily)

      Text(this.getModeDescription())
        .fontSize(15)
        .fontColor('rgba(255,255,255,0.92)')
        .fontFamily(this.appFontFamily)

      Text(this.getReminderText())
        .fontSize(13)
        .fontColor('rgba(255, 216, 133, 1)')
        .fontFamily(this.appFontFamily)

      if (this.getOrientationReminderText().length > 0) {
        Text(this.getOrientationReminderText())
          .fontSize(13)
          .fontColor('rgba(127, 206, 255, 1)')
          .fontFamily(this.appFontFamily)
      }

      Column({ space: 6 }) {
        if (this.hasZoneType(InteractionZoneType.PAGE_TURN_PREV)) {
          this.buildLegendRow(InteractionZoneType.PAGE_TURN_PREV);
        }
        if (this.hasZoneType(InteractionZoneType.PAGE_TURN_NEXT)) {
          this.buildLegendRow(InteractionZoneType.PAGE_TURN_NEXT);
        }
        if (this.hasZoneType(InteractionZoneType.TOOLBAR_TOGGLE)) {
          this.buildLegendRow(InteractionZoneType.TOOLBAR_TOGGLE);
        }
      }
      .width('100%')

      Text('轻点任意位置关闭提示')
        .fontSize(13)
        .fontColor('rgba(255,255,255,0.72)')
        .fontFamily(this.appFontFamily)
        .margin({ top: 4 })
    }
    .width('100%')
    .padding(22)
    .borderRadius(18)
    .backgroundColor('rgba(12, 12, 16, 0.86)')
    .shadow({
      radius: 18,
      color: 'rgba(0, 0, 0, 0.42)',
      offsetX: 0,
      offsetY: 4
    })
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.72)')
        .blur(12)

      Stack() {
        ForEach(this.zones, (zone: InteractionZone) => {
          this.buildZone(zone);
        }, (zone: InteractionZone, index: number) => `${zone.type}_${index}`)
      }
      .width(this.params.componentWidth)
      .height(this.params.componentHeight)

      Column() {
        this.buildInstructionPanel();
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ left: 20, right: 20, bottom: 56 })
    }
    .width('100%')
    .height('100%')
    .opacity(this.overlayOpacity)
    .animation({ duration: 280, curve: Curve.EaseOut })
    .onClick(() => {
      logger.info(TAG, 'overlay dismissed by tap');
      this.params.onDismiss();
    })
    .hitTestBehavior(HitTestMode.Block)
  }
}
