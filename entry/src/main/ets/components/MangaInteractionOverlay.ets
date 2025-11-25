/**
 * 漫画阅读器交互提示Overlay组件（优化版）
 * 为不同阅读模式和设备方向提供定制化的交互提示
 * 支持：单页LTR/RTL/TTB、双页、条漫、连续垂直等模式
 */

import { logger } from '../Utils/Logger';
import { ReadingMode, ReadingDirection } from '../Models/MangaModels';

const TAG = 'MangaInteractionOverlay';

// 交互区域类型
export enum InteractionZoneType {
  PAGE_TURN_PREV = 'PAGE_TURN_PREV',        // 上一页区域（蓝色）
  PAGE_TURN_NEXT = 'PAGE_TURN_NEXT',        // 下一页区域（绿色）
  TOOLBAR_TOGGLE = 'TOOLBAR_TOGGLE',        // 工具栏切换区域（橙色）
  SCROLL_AREA = 'SCROLL_AREA'               // 滚动区域（紫色，仅条漫）
}

// 交互区域定义
export interface InteractionZone {
  type: InteractionZoneType;
  left: number;
  top: number;
  width: number;
  height: number;
  label: string;
  icon?: string; // 图标文字（如箭头符号）
}

// 组件参数
export interface MangaInteractionOverlayParams {
  readingMode: ReadingMode;
  readingDirection: ReadingDirection;
  componentWidth: number;
  componentHeight: number;
  deviceOrientation: 'portrait' | 'landscape' | 'square';
  statusBarHeight: number;
  navigationBarHeight: number;
  onDismiss: () => void;
}

// 颜色方案
interface ColorScheme {
  background: string;
  border: string;
  text: string;
}

@Component
export struct MangaInteractionOverlay {
  @Prop params: MangaInteractionOverlayParams;
  @State private zones: InteractionZone[] = [];
  @State private overlayOpacity: number = 0;
  @State private modeDescription: string = '';

  aboutToAppear(): void {
    this.calculateZones();
    this.modeDescription = this.getModeDescription();
    
    // 淡入动画
    setTimeout(() => {
      this.overlayOpacity = 1;
    }, 50);
    
    logger.info(TAG, `交互提示Overlay已加载: 阅读模式=${this.params.readingMode}, 阅读方向=${this.params.readingDirection}, 设备方向=${this.params.deviceOrientation}`);
  }

  /**
   * 根据阅读模式、阅读方向和设备方向计算交互区域
   */
  private calculateZones(): void {
    const zones: InteractionZone[] = [];
    const width = this.params.componentWidth;
    const height = this.params.componentHeight;
    const direction = this.params.readingDirection;
    
    // 条漫类模式：忽略阅读方向，统一处理
    if (this.params.readingMode === ReadingMode.WEBTOON ||
        this.params.readingMode === ReadingMode.WEBTOON_WITH_GAP ||
        this.params.readingMode === ReadingMode.CONTINUOUS_VERTICAL) {
      this.calculateWebtoonZones(zones, width, height);
      this.zones = zones;
      logger.debug(TAG, `已计算${zones.length}个交互区域，模式: ${this.params.readingMode}（条漫）`);
      return;
    }
    
    // 单页和双页模式：根据阅读模式和阅读方向决定布局
    if (this.params.readingMode === ReadingMode.DOUBLE_PAGE) {
      // 双页模式根据阅读方向调整
      if (direction === ReadingDirection.RIGHT_TO_LEFT) {
        this.calculateDoublePageRTLZones(zones, width, height);
      } else {
        this.calculateDoublePageZones(zones, width, height);
      }
    } else {
      // 单页模式：优先根据阅读模式判断，其次根据阅读方向
      // 修复：SINGLE_PAGE_RTL 和 SINGLE_PAGE_TTB 模式需要正确显示对应的overlay
      if (this.params.readingMode === ReadingMode.SINGLE_PAGE_RTL) {
        // 单页从右到左模式
        this.calculateRTLZones(zones, width, height);
      } else if (this.params.readingMode === ReadingMode.SINGLE_PAGE_TTB) {
        // 单页从上到下模式
        this.calculateTTBZones(zones, width, height);
      } else if (this.params.readingMode === ReadingMode.SINGLE_PAGE_LTR) {
        // 单页从左到右模式
        this.calculateLTRZones(zones, width, height);
      } else {
        // SINGLE_PAGE 默认模式：根据阅读方向决定
        switch (direction) {
          case ReadingDirection.RIGHT_TO_LEFT:
            this.calculateRTLZones(zones, width, height);
            break;
          case ReadingDirection.TOP_TO_BOTTOM:
          case ReadingDirection.VERTICAL:
            this.calculateTTBZones(zones, width, height);
            break;
          case ReadingDirection.LEFT_TO_RIGHT:
          default:
            this.calculateLTRZones(zones, width, height);
            break;
        }
      }
    }
    
    this.zones = zones;
    logger.debug(TAG, `已计算${zones.length}个交互区域，模式: ${this.params.readingMode}, 方向: ${direction}`);
  }

  /**
   * 条漫模式区域计算
   */
  private calculateWebtoonZones(zones: InteractionZone[], width: number, height: number): void {
    // 条漫模式：整个区域都是切换工具栏，提示滑动操作
    zones.push({
      type: InteractionZoneType.TOOLBAR_TOGGLE,
      left: 0,
      top: 0,
      width: width,
      height: height,
      label: '点击显示/隐藏工具栏',
      icon: '⚙️'
    });
  }

  /**
   * 上下翻页模式区域计算
   */
  private calculateTTBZones(zones: InteractionZone[], width: number, height: number): void {
    const topHeight = height * 0.3;
    const middleHeight = height * 0.4;
    const bottomHeight = height * 0.3;
    
    // 上部：上一页
    zones.push({
      type: InteractionZoneType.PAGE_TURN_PREV,
      left: 0,
      top: 0,
      width: width,
      height: topHeight,
      label: '上一页',
      icon: '↑'
    });
    
    // 中部：工具栏
    zones.push({
      type: InteractionZoneType.TOOLBAR_TOGGLE,
      left: 0,
      top: topHeight,
      width: width,
      height: middleHeight,
      label: '显示/隐藏工具栏',
      icon: '⚙️'
    });
    
    // 下部：下一页
    zones.push({
      type: InteractionZoneType.PAGE_TURN_NEXT,
      left: 0,
      top: topHeight + middleHeight,
      width: width,
      height: bottomHeight,
      label: '下一页',
      icon: '↓'
    });
  }

  /**
   * 从右到左翻页模式区域计算
   */
  private calculateRTLZones(zones: InteractionZone[], width: number, height: number): void {
    const leftWidth = width * 0.3;
    const middleWidth = width * 0.4;
    const rightWidth = width * 0.3;
    
    // 左侧：下一页（RTL模式）
    zones.push({
      type: InteractionZoneType.PAGE_TURN_NEXT,
      left: 0,
      top: 0,
      width: leftWidth,
      height: height,
      label: '下一页',
      icon: '←'
    });
    
    // 中间：工具栏
    zones.push({
      type: InteractionZoneType.TOOLBAR_TOGGLE,
      left: leftWidth,
      top: 0,
      width: middleWidth,
      height: height,
      label: '显示/隐藏工具栏',
      icon: '⚙️'
    });
    
    // 右侧：上一页（RTL模式）
    zones.push({
      type: InteractionZoneType.PAGE_TURN_PREV,
      left: leftWidth + middleWidth,
      top: 0,
      width: rightWidth,
      height: height,
      label: '上一页',
      icon: '→'
    });
  }

  /**
   * 从左到右翻页模式区域计算
   */
  private calculateLTRZones(zones: InteractionZone[], width: number, height: number): void {
    const leftWidth = width * 0.3;
    const middleWidth = width * 0.4;
    const rightWidth = width * 0.3;
    
    // 左侧：上一页
    zones.push({
      type: InteractionZoneType.PAGE_TURN_PREV,
      left: 0,
      top: 0,
      width: leftWidth,
      height: height,
      label: '上一页',
      icon: '←'
    });
    
    // 中间：工具栏
    zones.push({
      type: InteractionZoneType.TOOLBAR_TOGGLE,
      left: leftWidth,
      top: 0,
      width: middleWidth,
      height: height,
      label: '显示/隐藏工具栏',
      icon: '⚙️'
    });
    
    // 右侧：下一页
    zones.push({
      type: InteractionZoneType.PAGE_TURN_NEXT,
      left: leftWidth + middleWidth,
      top: 0,
      width: rightWidth,
      height: height,
      label: '下一页',
      icon: '→'
    });
  }

  /**
   * 双页模式区域计算（LTR - 从左到右）
   */
  private calculateDoublePageZones(zones: InteractionZone[], width: number, height: number): void {
    const edgeWidth = width * 0.25;
    const middleWidth = width * 0.5;
    
    // 左侧边缘：上一页
    zones.push({
      type: InteractionZoneType.PAGE_TURN_PREV,
      left: 0,
      top: 0,
      width: edgeWidth,
      height: height,
      label: '上一页',
      icon: '←'
    });
    
    // 中间区域：工具栏
    zones.push({
      type: InteractionZoneType.TOOLBAR_TOGGLE,
      left: edgeWidth,
      top: 0,
      width: middleWidth,
      height: height,
      label: '显示/隐藏工具栏',
      icon: '⚙️'
    });
    
    // 右侧边缘：下一页
    zones.push({
      type: InteractionZoneType.PAGE_TURN_NEXT,
      left: edgeWidth + middleWidth,
      top: 0,
      width: edgeWidth,
      height: height,
      label: '下一页',
      icon: '→'
    });
  }

  /**
   * 双页模式区域计算（RTL - 从右到左）
   */
  private calculateDoublePageRTLZones(zones: InteractionZone[], width: number, height: number): void {
    const edgeWidth = width * 0.25;
    const middleWidth = width * 0.5;
    
    // 左侧边缘：下一页（RTL模式）
    zones.push({
      type: InteractionZoneType.PAGE_TURN_NEXT,
      left: 0,
      top: 0,
      width: edgeWidth,
      height: height,
      label: '下一页',
      icon: '←'
    });
    
    // 中间区域：工具栏
    zones.push({
      type: InteractionZoneType.TOOLBAR_TOGGLE,
      left: edgeWidth,
      top: 0,
      width: middleWidth,
      height: height,
      label: '显示/隐藏工具栏',
      icon: '⚙️'
    });
    
    // 右侧边缘：上一页（RTL模式）
    zones.push({
      type: InteractionZoneType.PAGE_TURN_PREV,
      left: edgeWidth + middleWidth,
      top: 0,
      width: edgeWidth,
      height: height,
      label: '上一页',
      icon: '→'
    });
  }

  /**
   * 获取颜色方案
   */
  private getColorScheme(type: InteractionZoneType): ColorScheme {
    switch (type) {
      case InteractionZoneType.PAGE_TURN_PREV:
        return {
          background: 'rgba(33, 150, 243, 0.2)',  // 蓝色
          border: 'rgba(33, 150, 243, 0.7)',
          text: 'rgba(33, 150, 243, 1)'
        };
      case InteractionZoneType.PAGE_TURN_NEXT:
        return {
          background: 'rgba(76, 175, 80, 0.2)',   // 绿色
          border: 'rgba(76, 175, 80, 0.7)',
          text: 'rgba(76, 175, 80, 1)'
        };
      case InteractionZoneType.TOOLBAR_TOGGLE:
        return {
          background: 'rgba(255, 152, 0, 0.2)',   // 橙色
          border: 'rgba(255, 152, 0, 0.7)',
          text: 'rgba(255, 152, 0, 1)'
        };
      case InteractionZoneType.SCROLL_AREA:
        return {
          background: 'rgba(156, 39, 176, 0.2)',  // 紫色
          border: 'rgba(156, 39, 176, 0.7)',
          text: 'rgba(156, 39, 176, 1)'
        };
      default:
        return {
          background: 'rgba(255, 255, 255, 0.2)',
          border: 'rgba(255, 255, 255, 0.7)',
          text: 'rgba(255, 255, 255, 1)'
        };
    }
  }

  /**
   * 获取阅读模式描述
   */
  private getModeDescription(): string {
    switch (this.params.readingMode) {
      case ReadingMode.WEBTOON:
      case ReadingMode.WEBTOON_WITH_GAP:
        return '条漫模式：上下滑动阅读';
      case ReadingMode.CONTINUOUS_VERTICAL:
        return '连续垂直：无缝滚动阅读';
      case ReadingMode.SINGLE_PAGE_TTB:
        return '单页模式：上下翻页';
      case ReadingMode.SINGLE_PAGE_RTL:
        return '单页模式：从右到左翻页';
      case ReadingMode.DOUBLE_PAGE:
        return '双页模式：同时显示两页';
      case ReadingMode.SINGLE_PAGE:
      case ReadingMode.SINGLE_PAGE_LTR:
      default:
        return '单页模式：从左到右翻页';
    }
  }

  /**
   * 渲染单个交互区域
   */
  @Builder
  private buildZone(zone: InteractionZone): void {
    Stack() {
      // 半透明背景
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.getColorScheme(zone.type).background)
      
      // 虚线边框
      Column()
        .width('100%')
        .height('100%')
        .border({
          width: 3,
          color: this.getColorScheme(zone.type).border,
          style: BorderStyle.Dashed
        })
      
      // 中心内容：图标 + 文字
      Column() {
        if (zone.icon) {
          Text(zone.icon)
            .fontSize(48)
            .margin({ bottom: 12 })
        }
        
        Text(zone.label)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getColorScheme(zone.type).text)
          .textAlign(TextAlign.Center)
          .textShadow({
            radius: 4,
            color: 'rgba(0, 0, 0, 0.6)',
            offsetX: 0,
            offsetY: 2
          })
      }
      .justifyContent(FlexAlign.Center)
    }
    .width(zone.width)  // vp单位
    .height(zone.height) // vp单位
    .position({ x: zone.left, y: zone.top }) // vp单位
  }

  /**
   * 渲染说明面板
   */
  @Builder
  private buildInstructionPanel(): void {
    Column({ space: 12 }) {
      // 标题
      Text('交互说明')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
      
      // 模式描述
      Text(this.modeDescription)
        .fontSize(16)
        .fontColor('rgba(255, 255, 255, 0.9)')
        .margin({ bottom: 8 })
      
      // 区域说明
      Column({ space: 8 }) {
        if (this.hasZoneType(InteractionZoneType.PAGE_TURN_PREV)) {
          Row({ space: 8 }) {
            Text('●')
              .fontSize(16)
              .fontColor('rgba(33, 150, 243, 1)')
            Text('蓝色区域：上一页')
              .fontSize(15)
              .fontColor('rgba(33, 150, 243, 1)')
          }
        }
        
        if (this.hasZoneType(InteractionZoneType.PAGE_TURN_NEXT)) {
          Row({ space: 8 }) {
            Text('●')
              .fontSize(16)
              .fontColor('rgba(76, 175, 80, 1)')
            Text('绿色区域：下一页')
              .fontSize(15)
              .fontColor('rgba(76, 175, 80, 1)')
          }
        }
        
        if (this.hasZoneType(InteractionZoneType.TOOLBAR_TOGGLE)) {
          Row({ space: 8 }) {
            Text('●')
              .fontSize(16)
              .fontColor('rgba(255, 152, 0, 1)')
            Text('橙色区域：显示/隐藏工具栏')
              .fontSize(15)
              .fontColor('rgba(255, 152, 0, 1)')
          }
        }
      }
      .alignItems(HorizontalAlign.Start)
      
      // 关闭提示
      Text('点击任意位置关闭提示')
        .fontSize(14)
        .fontColor('rgba(255, 255, 255, 0.7)')
        .margin({ top: 12 })
    }
    .padding(24)
    .borderRadius(16)
    .backgroundColor('rgba(0, 0, 0, 0.85)')
    .shadow({
      radius: 20,
      color: 'rgba(0, 0, 0, 0.5)',
      offsetX: 0,
      offsetY: 4
    })
  }

  /**
   * 检查是否有指定类型的区域
   */
  private hasZoneType(type: InteractionZoneType): boolean {
    return this.zones.some((zone: InteractionZone) => zone.type === type);
  }

  build() {
    Stack() {
      // 半透明黑色背景
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.75)')
        .blur(10)
      
      // 渲染所有交互区域
      Stack() {
        ForEach(this.zones, (zone: InteractionZone) => {
          this.buildZone(zone);
        }, (zone: InteractionZone, index: number) => `zone_${index}_${zone.type}`)
      }
      .width(this.params.componentWidth)  // vp单位
      .height(this.params.componentHeight) // vp单位
      
      // 说明面板（居中或底部）
      Column() {
        this.buildInstructionPanel();
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ bottom: 60 })
    }
    .width('100%')
    .height('100%')
    .opacity(this.overlayOpacity)
    .animation({
      duration: 300,
      curve: Curve.EaseOut
    })
    .onClick(() => {
      logger.info(TAG, '用户点击关闭交互提示');
      this.params.onDismiss();
    })
    .hitTestBehavior(HitTestMode.Block) // 阻止事件穿透
  }
}
