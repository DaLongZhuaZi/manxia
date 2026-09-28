import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { TextReadingDirection, TextReadingMode } from 'manxia_core/src/main/ets/Models/TextReaderModels';

const TAG = 'TextReaderInteractionOverlay';
const OVERLAY_FADE_IN_DELAY_MS: number = 50;

export enum TextInteractionZoneType {
  PAGE_TURN_PREV = 'PAGE_TURN_PREV',
  PAGE_TURN_NEXT = 'PAGE_TURN_NEXT',
  TOOLBAR_TOGGLE = 'TOOLBAR_TOGGLE'
}

export interface TextInteractionZone {
  type: TextInteractionZoneType;
  left: number;
  top: number;
  width: number;
  height: number;
  label: string;
}

export interface TextReaderInteractionOverlayParams {
  readerLabel: string;
  readingMode: TextReadingMode;
  readingDirection: TextReadingDirection;
  tapToTurn: boolean;
  componentWidth: number;
  componentHeight: number;
  onDismiss: () => void;
}

interface ColorScheme {
  background: string;
  border: string;
  text: string;
}

@Component
export struct TextReaderInteractionOverlay {
  @Prop params: TextReaderInteractionOverlayParams;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State private zones: TextInteractionZone[] = [];
  @State private overlayOpacity: number = 0;

  aboutToAppear(): void {
    this.zones = this.buildZones();
    setTimeout(() => {
      this.overlayOpacity = 1;
    }, OVERLAY_FADE_IN_DELAY_MS);
    logger.info(
      TAG,
      `overlay ready: reader=${this.params.readerLabel}, mode=${this.params.readingMode}, direction=${this.params.readingDirection}, tapToTurn=${this.params.tapToTurn}`
    );
  }

  private isScrollLikeMode(): boolean {
    return this.params.readingMode === TextReadingMode.SCROLL ||
      this.params.readingMode === TextReadingMode.AUTO_SCROLL;
  }

  private isDualPageMode(): boolean {
    return this.params.readingMode === TextReadingMode.DUAL_PAGE;
  }

  private isReversePagingDirection(): boolean {
    return this.params.readingDirection !== TextReadingDirection.HORIZONTAL;
  }

  private buildZones(): TextInteractionZone[] {
    const width = Math.max(1, this.params.componentWidth);
    const height = Math.max(1, this.params.componentHeight);

    if (this.isScrollLikeMode()) {
      return [{
        type: TextInteractionZoneType.TOOLBAR_TOGGLE,
        left: 0,
        top: 0,
        width,
        height,
        label: '双指轻点屏幕\n呼出工具栏'
      }];
    }

    if (!this.params.tapToTurn) {
      return [{
        type: TextInteractionZoneType.TOOLBAR_TOGGLE,
        left: 0,
        top: 0,
        width,
        height,
        label: '单击屏幕\n显示或隐藏工具栏'
      }];
    }

    if (this.isDualPageMode()) {
      const edgeWidth = width / 6;
      const middleWidth = width - edgeWidth * 2;
      return [
        {
          type: TextInteractionZoneType.PAGE_TURN_PREV,
          left: 0,
          top: 0,
          width: edgeWidth,
          height,
          label: '上一页'
        },
        {
          type: TextInteractionZoneType.TOOLBAR_TOGGLE,
          left: edgeWidth,
          top: 0,
          width: middleWidth,
          height,
          label: '中间大区域\n显示工具栏'
        },
        {
          type: TextInteractionZoneType.PAGE_TURN_NEXT,
          left: edgeWidth + middleWidth,
          top: 0,
          width: edgeWidth,
          height,
          label: '下一页'
        }
      ];
    }

    const sideWidth = width / 3;
    const middleWidth = width - sideWidth * 2;
    const leftLabel = this.isReversePagingDirection() ? '下一页' : '上一页';
    const rightLabel = this.isReversePagingDirection() ? '上一页' : '下一页';
    return [
      {
        type: this.isReversePagingDirection()
          ? TextInteractionZoneType.PAGE_TURN_NEXT
          : TextInteractionZoneType.PAGE_TURN_PREV,
        left: 0,
        top: 0,
        width: sideWidth,
        height,
        label: leftLabel
      },
      {
        type: TextInteractionZoneType.TOOLBAR_TOGGLE,
        left: sideWidth,
        top: 0,
        width: middleWidth,
        height,
        label: '显示/隐藏\n工具栏'
      },
      {
        type: this.isReversePagingDirection()
          ? TextInteractionZoneType.PAGE_TURN_PREV
          : TextInteractionZoneType.PAGE_TURN_NEXT,
        left: sideWidth + middleWidth,
        top: 0,
        width: sideWidth,
        height,
        label: rightLabel
      }
    ];
  }

  private getColorScheme(type: TextInteractionZoneType): ColorScheme {
    switch (type) {
      case TextInteractionZoneType.PAGE_TURN_PREV:
        return {
          background: 'rgba(33, 150, 243, 0.18)',
          border: 'rgba(33, 150, 243, 0.78)',
          text: 'rgba(127, 206, 255, 1)'
        };
      case TextInteractionZoneType.PAGE_TURN_NEXT:
        return {
          background: 'rgba(76, 175, 80, 0.18)',
          border: 'rgba(76, 175, 80, 0.78)',
          text: 'rgba(156, 255, 178, 1)'
        };
      case TextInteractionZoneType.TOOLBAR_TOGGLE:
      default:
        return {
          background: 'rgba(255, 152, 0, 0.18)',
          border: 'rgba(255, 152, 0, 0.82)',
          text: 'rgba(255, 216, 133, 1)'
        };
    }
  }

  private getModeDescription(): string {
    if (this.isScrollLikeMode()) {
      return `${this.params.readerLabel}当前为上下滚动模式：单指上下滑动阅读，工具栏需要双指轻点屏幕呼出。`;
    }

    if (!this.params.tapToTurn) {
      return `${this.params.readerLabel}当前已关闭点击翻页：单击屏幕只会显示或隐藏工具栏，不会直接翻页。`;
    }

    if (this.isDualPageMode()) {
      return `${this.params.readerLabel}当前为双页模式：左右窄边缘翻页，中间大区域显示或隐藏工具栏。`;
    }

    return this.isReversePagingDirection()
      ? `${this.params.readerLabel}当前为分页模式（反向顺序）：左侧下一页，中间显示工具栏，右侧上一页。`
      : `${this.params.readerLabel}当前为分页模式：左侧上一页，中间显示工具栏，右侧下一页。`;
  }

  private getReminderText(): string {
    if (this.isScrollLikeMode()) {
      return '重要：上下滚动模式下，请用双指轻点屏幕呼出工具栏。';
    }
    if (!this.params.tapToTurn) {
      return '重要：你已关闭点击翻页。单击只控制工具栏；如果切换到上下滚动，呼出工具栏依然需要双指轻点。';
    }
    return '提示：分页或双页模式可按热区单击翻页；如果切换到上下滚动模式，呼出工具栏会改为双指轻点。';
  }

  private getLegendText(type: TextInteractionZoneType): string {
    switch (type) {
      case TextInteractionZoneType.PAGE_TURN_PREV:
        return '蓝色区域：翻到上一页';
      case TextInteractionZoneType.PAGE_TURN_NEXT:
        return '绿色区域：翻到下一页';
      case TextInteractionZoneType.TOOLBAR_TOGGLE:
      default:
        return this.isScrollLikeMode()
          ? '橙色区域：双指轻点屏幕，显示或隐藏工具栏'
          : '橙色区域：显示或隐藏工具栏';
    }
  }

  private hasZoneType(type: TextInteractionZoneType): boolean {
    return this.zones.some((zone: TextInteractionZone) => zone.type === type);
  }

  @Builder
  private buildZone(zone: TextInteractionZone): void {
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

      Column() {
        Text(zone.label)
          .fontSize(this.isScrollLikeMode() || !this.params.tapToTurn ? 24 : 18)
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
  private buildLegendRow(type: TextInteractionZoneType): void {
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

      Column({ space: 6 }) {
        if (this.hasZoneType(TextInteractionZoneType.PAGE_TURN_PREV)) {
          this.buildLegendRow(TextInteractionZoneType.PAGE_TURN_PREV);
        }
        if (this.hasZoneType(TextInteractionZoneType.PAGE_TURN_NEXT)) {
          this.buildLegendRow(TextInteractionZoneType.PAGE_TURN_NEXT);
        }
        if (this.hasZoneType(TextInteractionZoneType.TOOLBAR_TOGGLE)) {
          this.buildLegendRow(TextInteractionZoneType.TOOLBAR_TOGGLE);
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
        ForEach(this.zones, (zone: TextInteractionZone) => {
          this.buildZone(zone);
        }, (zone: TextInteractionZone, index: number) => `${zone.type}_${index}`)
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
