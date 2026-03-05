/**
 * 小说阅读器字体设置面板
 * 独立对话框，提供字体大小、行高、页边距、对齐、粗细、字体选择等设置
 * 风格与漫画阅读器对话框一致：竖屏底部上滑、横屏右侧滑入
 */

import {
  TextReaderSettings,
  TextAlignment,
  BackgroundType,
  DEFAULT_TEXT_STYLE,
  DEFAULT_PAGE_MARGINS
} from '../Models/TextReaderModels';
import { logger } from '../Utils/Logger';
import { ThemeManager } from '../Framework/Managers/ThemeManager';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeType } from '../Framework/Managers/ThemeManager';
import { getFontManager, SystemFont, CustomFont } from '../Framework/Managers/FontManager';
import { curves, UIContext, display } from '@kit.ArkUI';

const TAG = 'TextFontSettingsPanel';

/**
 * 文字对齐选项接口
 */
interface AlignmentOption {
  text: string;
  align: TextAlignment;
}

/**
 * 字体粗细选项接口
 */
interface WeightOption {
  text: string;
  weight: number;
}

/**
 * 回调接口
 */
interface TextFontSettingsCallbacks {
  onSettingsChange: (settings: TextReaderSettings) => void;
  onClose: () => void;
}

@Component
export struct TextFontSettingsPanel {
  @Prop settings: TextReaderSettings;
  @Prop isVisible: boolean;
  @Prop callbacks: TextFontSettingsCallbacks;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  // 动画状态
  @State private panelOpacity: number = 0;
  @State private panelTranslateY: number = 300;
  @State private panelTranslateX: number = 320;
  @State private backdropOpacity: number = 0;
  @State private themeState: ThemeAwareState = new ThemeAwareState();
  @State private isLandscape: boolean = false;

  // 字体列表
  @State private systemFonts: SystemFont[] = [];
  @State private customFonts: CustomFont[] = [];
  @State private showFontPicker: boolean = true;

  /** 预览文本 */
  private previewText: string = '愿中国青年都摆脱冷气，只是向上走，不必听自暴自弃者流的话。能做事的做事，能发声的发声。有一分热，发一分光，就令萤火一般，也可以在黑暗里发一点光，不必等候炬火。此后如竟没有炬火：我便是唯一的光。倘若有了炬火，出了太阳，我们自然心悦诚服的消失，不但毫无不平，而且还要随喜赞美这炬火或太阳；因为他照了人类，连我都在内。';
  private uiContext: UIContext | undefined = undefined;

  aboutToAppear() {
    this.uiContext = this.getUIContext();
    this.detectScreenOrientation();

    ThemeAwareHelper.initializeThemeAware('TextFontSettingsPanel', this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });

    // 加载字体列表
    const fontManager = getFontManager();
    this.systemFonts = fontManager.getSystemFonts();
    this.customFonts = fontManager.getCustomFonts();

    // 播放入场动画
    setTimeout(() => {
      this.showPanel();
    }, 50);
  }

  aboutToDisappear() {
    ThemeAwareHelper.cleanupThemeAware('TextFontSettingsPanel');
  }

  private detectScreenOrientation(): void {
    try {
      const displayInfo = display.getDefaultDisplaySync();
      if (displayInfo) {
        const w = displayInfo.width / (displayInfo.densityPixels || 1);
        const h = displayInfo.height / (displayInfo.densityPixels || 1);
        this.isLandscape = w > h;
      }
    } catch (error) {
      logger.error(TAG, `屏幕方向检测失败: ${String(error)}`);
    }
  }

  private showPanel(): void {
    if (!this.uiContext) {
      this.panelOpacity = 1;
      this.panelTranslateY = 0;
      this.panelTranslateX = 0;
      this.backdropOpacity = 0.5;
      return;
    }

    this.uiContext.animateTo({
      duration: 200,
      curve: curves.initCurve(Curve.EaseOut)
    }, () => {
      this.backdropOpacity = 0.5;
    });

    if (this.isLandscape) {
      this.uiContext.animateTo({
        duration: 250,
        curve: curves.initCurve(Curve.EaseOut)
      }, () => {
        this.panelOpacity = 1;
        this.panelTranslateX = 0;
      });
    } else {
      this.uiContext.animateTo({
        duration: 300,
        curve: curves.initCurve(Curve.EaseOut)
      }, () => {
        this.panelOpacity = 1;
        this.panelTranslateY = 0;
      });
    }
  }

  private hidePanel(): void {
    if (this.callbacks.onClose) {
      this.callbacks.onClose();
    }

    if (this.uiContext) {
      if (this.isLandscape) {
        this.uiContext.animateTo({
          duration: 200,
          curve: curves.initCurve(Curve.EaseIn)
        }, () => {
          this.panelOpacity = 0;
          this.panelTranslateX = 320;
        });
      } else {
        this.uiContext.animateTo({
          duration: 200,
          curve: curves.initCurve(Curve.EaseIn)
        }, () => {
          this.panelOpacity = 0;
          this.panelTranslateY = 300;
        });
      }

      this.uiContext.animateTo({
        duration: 200,
        curve: curves.initCurve(Curve.EaseIn)
      }, () => {
        this.backdropOpacity = 0;
      });
    }
  }

  /**
   * 通知父组件设置变化
   */
  private notifyChange(): void {
    if (this.callbacks.onSettingsChange) {
      this.callbacks.onSettingsChange(this.settings);
    }
  }

  private ensurePageMargins(): void {
    if (!this.settings.pageMargins) {
      this.settings.pageMargins = {
        top: DEFAULT_PAGE_MARGINS.top,
        bottom: DEFAULT_PAGE_MARGINS.bottom,
        left: DEFAULT_PAGE_MARGINS.left,
        right: DEFAULT_PAGE_MARGINS.right
      };
    }
  }

  private updateHorizontalMargins(value: number): void {
    this.ensurePageMargins();
    const margin = Math.round(value);
    this.settings.pageMargins = {
      top: this.settings.pageMargins.top,
      bottom: this.settings.pageMargins.bottom,
      left: margin,
      right: margin
    };
    this.notifyChange();
  }

  private updateTopMargin(value: number): void {
    this.ensurePageMargins();
    this.settings.pageMargins = {
      top: Math.round(value),
      bottom: this.settings.pageMargins.bottom,
      left: this.settings.pageMargins.left,
      right: this.settings.pageMargins.right
    };
    this.notifyChange();
  }

  private updateBottomMargin(value: number): void {
    this.ensurePageMargins();
    this.settings.pageMargins = {
      top: this.settings.pageMargins.top,
      bottom: Math.round(value),
      left: this.settings.pageMargins.left,
      right: this.settings.pageMargins.right
    };
    this.notifyChange();
  }

  /**
   * 恢复字体设置为默认值
   */
  private resetFontSettings(): void {
    this.settings.textStyle = {
      fontSize: DEFAULT_TEXT_STYLE.fontSize,
      lineHeight: DEFAULT_TEXT_STYLE.lineHeight,
      paragraphSpacing: DEFAULT_TEXT_STYLE.paragraphSpacing,
      firstLineIndent: DEFAULT_TEXT_STYLE.firstLineIndent,
      letterSpacing: DEFAULT_TEXT_STYLE.letterSpacing,
      textColor: this.settings.textStyle.textColor,
      fontWeight: DEFAULT_TEXT_STYLE.fontWeight,
      fontFamily: DEFAULT_TEXT_STYLE.fontFamily,
      textAlignment: DEFAULT_TEXT_STYLE.textAlignment
    };
    this.settings.pageMargins = {
      top: DEFAULT_PAGE_MARGINS.top,
      bottom: DEFAULT_PAGE_MARGINS.bottom,
      left: DEFAULT_PAGE_MARGINS.left,
      right: DEFAULT_PAGE_MARGINS.right
    };
    this.notifyChange();
    logger.info(TAG, '字体设置已恢复默认');
  }

  /**
   * 获取当前字体显示名称
   */
  private getCurrentFontDisplayName(): string {
    const currentFamily = this.settings.textStyle.fontFamily;
    const systemFont = this.systemFonts.find(f => f.name === currentFamily);
    if (systemFont) return systemFont.displayName;
    const customFont = this.customFonts.find(f => f.familyName === currentFamily);
    if (customFont) return customFont.displayName;
    return '系统默认';
  }

  // ==================== 竖屏面板 ====================
  @Builder
  buildPortraitPanel() {
    Column() {
      // 标题栏
      Row() {
        Text('字体设置')
          .fontSize(18)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Button() {
          Image($r('app.media.ic_close'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.text_secondary'))
        }
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .onClick(() => this.hidePanel())
      }
      .width('100%')
      .margin({ bottom: 16 })

      // 可滚动内容区域
      Scroll() {
        Column({ space: 20 }) {
          this.buildFontContent()
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      // 底部按钮
      Row({ space: 12 }) {
        Button('恢复默认')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(Color.White)
          .backgroundColor('#E53935')
          .layoutWeight(1)
          .height(40)
          .onClick(() => this.resetFontSettings())
        Button('确认')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_on_accent'))
          .backgroundColor($r('app.color.accent'))
          .layoutWeight(1)
          .height(40)
          .onClick(() => this.hidePanel())
      }
      .width('100%')
    }
    .width('100%')
    .constraintSize({ maxHeight: '75%' })
    .padding(20)
    .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
    .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
    .borderRadius({ topLeft: 16, topRight: 16 })
    .opacity(this.panelOpacity)
    .translate({ x: 0, y: this.panelTranslateY })
    .position({ x: 0, y: '100%' })
    .translate({ x: 0, y: '-100%' })
    .hitTestBehavior(HitTestMode.Default)
  }

  // ==================== 横屏面板 ====================
  @Builder
  buildLandscapePanel() {
    Row() {
      // 左侧空白区域（点击关闭）
      Column()
        .layoutWeight(1)
        .height('100%')
        .onClick(() => this.hidePanel())

      // 右侧设置面板
      Column() {
        // 标题
        Row() {
          Text('字体设置')
            .fontSize(16)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)

          Button() {
            Image($r('app.media.ic_close'))
              .width(18)
              .height(18)
              .fillColor($r('app.color.text_secondary'))
          }
          .width(32)
          .height(32)
          .backgroundColor(Color.Transparent)
          .onClick(() => this.hidePanel())
        }
        .width('100%')
        .margin({ bottom: 12 })

        // 可滚动内容
        Scroll() {
          Column({ space: 16 }) {
            this.buildFontContentCompact()
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)

        // 底部按钮
        Row({ space: 8 }) {
          Button('恢复默认')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(Color.White)
            .backgroundColor('#E53935')
            .layoutWeight(1)
            .height(32)
            .onClick(() => this.resetFontSettings())
          Button('确认')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor($r('app.color.text_on_accent'))
            .backgroundColor($r('app.color.accent'))
            .layoutWeight(1)
            .height(32)
            .onClick(() => this.hidePanel())
        }
        .width('100%')
      }
      .width(320)
      .height('100%')
      .padding(16)
      .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
      .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
      .borderRadius({ topLeft: 16, bottomLeft: 16 })
      .opacity(this.panelOpacity)
      .translate({ x: this.panelTranslateX })
      .hitTestBehavior(HitTestMode.Default)
    }
    .width('100%')
    .height('100%')
  }

  // ==================== 竖屏内容 ====================
  @Builder
  buildFontContent() {
    // 预览区域
    Column() {
      Text('预览效果')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ bottom: 8 })

      Text(this.previewText)
        .fontSize(this.settings.textStyle.fontSize)
        .lineHeight(this.settings.textStyle.fontSize * this.settings.textStyle.lineHeight)
        .fontColor(this.settings.textStyle.textColor)
        .letterSpacing(this.settings.textStyle.letterSpacing)
        .fontWeight(this.settings.textStyle.fontWeight)
        .fontFamily(this.settings.textStyle.fontFamily)
        .width('100%')
        .padding({
          left: this.settings.pageMargins.left,
          right: this.settings.pageMargins.right,
          top: 12,
          bottom: 12
        })
        .backgroundColor(this.settings.background.type === BackgroundType.COLOR ?
          this.settings.background.color || '#F5F0E1' : '#F5F0E1')
        .borderRadius(8)
        .maxLines(6)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')

    // 字体大小
    Column({ space: 8 }) {
      Row() {
        Text('字体大小')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(`${this.settings.textStyle.fontSize}`)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.accent'))
      }
      .width('100%')

      Row({ space: 12 }) {
        Button('A-')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .width(48)
          .height(36)
          .backgroundColor($r('app.color.background_secondary'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            if (this.settings.textStyle.fontSize > 12) {
              this.settings.textStyle.fontSize -= 1;
              this.notifyChange();
            }
          })

        Slider({
          value: this.settings.textStyle.fontSize,
          min: 12,
          max: 32,
          step: 1
        })
          .layoutWeight(1)
          .trackColor($r('app.color.divider'))
          .selectedColor($r('app.color.accent'))
          .onChange((value: number) => {
            this.settings.textStyle.fontSize = Math.round(value);
            this.notifyChange();
          })

        Button('A+')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .width(48)
          .height(36)
          .backgroundColor($r('app.color.background_secondary'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            if (this.settings.textStyle.fontSize < 32) {
              this.settings.textStyle.fontSize += 1;
              this.notifyChange();
            }
          })
      }
      .width('100%')
    }
    .width('100%')

    // 行高
    Column({ space: 8 }) {
      Row() {
        Text('行高')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(`${this.settings.textStyle.lineHeight.toFixed(1)}`)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.accent'))
      }
      .width('100%')

      Slider({
        value: this.settings.textStyle.lineHeight,
        min: 1.2,
        max: 3.0,
        step: 0.1
      })
        .width('100%')
        .trackColor($r('app.color.divider'))
        .selectedColor($r('app.color.accent'))
        .onChange((value: number) => {
          this.settings.textStyle.lineHeight = Math.round(value * 10) / 10;
          this.notifyChange();
        })
    }
    .width('100%')

    // 页边距
    Column({ space: 8 }) {
      Row() {
        Text('页边距')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(`${this.settings.pageMargins?.left ?? DEFAULT_PAGE_MARGINS.left}`)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.accent'))
      }
      .width('100%')

      Slider({
        value: this.settings.pageMargins?.left ?? DEFAULT_PAGE_MARGINS.left,
        min: 0,
        max: 80,
        step: 2
      })
        .width('100%')
        .trackColor($r('app.color.divider'))
        .selectedColor($r('app.color.accent'))
        .onChange((value: number) => {
          this.updateHorizontalMargins(value);
        })
    }
    .width('100%')

    // 上边距
    Column({ space: 8 }) {
      Row() {
        Text('上边距')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(`${this.settings.pageMargins?.top ?? DEFAULT_PAGE_MARGINS.top}`)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.accent'))
      }
      .width('100%')

      Slider({
        value: this.settings.pageMargins?.top ?? DEFAULT_PAGE_MARGINS.top,
        min: 0,
        max: 160,
        step: 2
      })
        .width('100%')
        .trackColor($r('app.color.divider'))
        .selectedColor($r('app.color.accent'))
        .onChange((value: number) => {
          this.updateTopMargin(value);
        })
    }
    .width('100%')

    // 下边距
    Column({ space: 8 }) {
      Row() {
        Text('下边距')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(`${this.settings.pageMargins?.bottom ?? DEFAULT_PAGE_MARGINS.bottom}`)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.accent'))
      }
      .width('100%')

      Slider({
        value: this.settings.pageMargins?.bottom ?? DEFAULT_PAGE_MARGINS.bottom,
        min: 0,
        max: 160,
        step: 2
      })
        .width('100%')
        .trackColor($r('app.color.divider'))
        .selectedColor($r('app.color.accent'))
        .onChange((value: number) => {
          this.updateBottomMargin(value);
        })
    }
    .width('100%')

    // 文字对齐
    Column({ space: 8 }) {
      Text('文字对齐')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Row({ space: 8 }) {
        ForEach(
          [
            { text: '左对齐', align: TextAlignment.LEFT },
            { text: '居中', align: TextAlignment.CENTER },
            { text: '右对齐', align: TextAlignment.RIGHT },
            { text: '两端', align: TextAlignment.JUSTIFY }
          ],
          (item: AlignmentOption) => {
            Column() {
              Text(item.text)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(this.settings.textStyle.textAlignment === item.align ?
                  $r('app.color.accent') : $r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .padding(10)
            .backgroundColor(this.settings.textStyle.textAlignment === item.align ?
              $r('app.color.accent_background') : Color.Transparent)
            .borderRadius(8)
            .onClick(() => {
              this.settings.textStyle.textAlignment = item.align;
              this.notifyChange();
            })
          }
        )
      }
      .width('100%')
    }
    .width('100%')

    // 字体粗细
    Column({ space: 8 }) {
      Row() {
        Text('字体粗细')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(`${this.settings.textStyle.fontWeight}`)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.accent'))
      }
      .width('100%')

      Row({ space: 8 }) {
        ForEach(
          [
            { text: '细', weight: 300 },
            { text: '常规', weight: 400 },
            { text: '中等', weight: 500 },
            { text: '粗', weight: 700 }
          ],
          (item: WeightOption) => {
            Column() {
              Text(item.text)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(this.settings.textStyle.fontWeight === item.weight ?
                  $r('app.color.accent') : $r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .padding(10)
            .backgroundColor(this.settings.textStyle.fontWeight === item.weight ?
              $r('app.color.accent_background') : Color.Transparent)
            .borderRadius(8)
            .onClick(() => {
              this.settings.textStyle.fontWeight = item.weight;
              this.notifyChange();
            })
          }
        )
      }
      .width('100%')
    }
    .width('100%')

    // 字体选择
    Column({ space: 8 }) {
      Row() {
        Text('字体')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(this.getCurrentFontDisplayName())
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.accent'))
      }
      .width('100%')
      .onClick(() => {
        this.showFontPicker = !this.showFontPicker;
      })

      if (this.showFontPicker) {
        Column({ space: 8 }) {
          Text('系统字体')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')

          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.systemFonts, (font: SystemFont) => {
              Column() {
                Text(font.displayName)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.settings.textStyle.fontFamily === font.name ?
                    $r('app.color.accent') : $r('app.color.text_secondary'))
              }
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .margin({ right: 8, bottom: 8 })
              .backgroundColor(this.settings.textStyle.fontFamily === font.name ?
                $r('app.color.accent_background') : Color.Transparent)
              .borderRadius(6)
              .onClick(() => {
                this.settings.textStyle.fontFamily = font.name;
                this.settings.textStyle.fontPath = '';
                this.notifyChange();
              })
            }, (font: SystemFont) => font.id)
          }
          .width('100%')

          if (this.customFonts.length > 0) {
            Text('自定义字体')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .margin({ top: 8 })

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.customFonts, (font: CustomFont) => {
                Column() {
                  Text(font.displayName)
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(this.settings.textStyle.fontFamily === font.familyName ?
                      $r('app.color.accent') : $r('app.color.text_secondary'))
                }
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .margin({ right: 8, bottom: 8 })
                .backgroundColor(this.settings.textStyle.fontFamily === font.familyName ?
                  $r('app.color.accent_background') : Color.Transparent)
                .borderRadius(6)
                .onClick(() => {
                  this.settings.textStyle.fontFamily = font.familyName;
                  this.settings.textStyle.fontPath = font.filePath;
                  this.notifyChange();
                })
              }, (font: CustomFont) => font.id)
            }
            .width('100%')
          }
        }
        .width('100%')
        .padding(12)
        .backgroundColor($r('app.color.background_secondary'))
        .borderRadius(8)
      }
    }
    .width('100%')
  }

  // ==================== 横屏紧凑内容 ====================
  @Builder
  buildFontContentCompact() {
    // 字体大小（紧凑）
    Row() {
      Text('字号')
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_primary'))
        .width(30)

      Slider({
        value: this.settings.textStyle.fontSize,
        min: 12,
        max: 32,
        step: 1
      })
        .layoutWeight(1)
        .trackColor($r('app.color.divider'))
        .selectedColor($r('app.color.accent'))
        .onChange((value: number) => {
          this.settings.textStyle.fontSize = Math.round(value);
          this.notifyChange();
        })

      Text(`${this.settings.textStyle.fontSize}`)
        .fontSize(10)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.accent'))
        .width(25)
    }
    .width('100%')

    // 行高（紧凑）
    Row() {
      Text('行高')
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_primary'))
        .width(30)

      Slider({
        value: this.settings.textStyle.lineHeight,
        min: 1.2,
        max: 3.0,
        step: 0.1
      })
        .layoutWeight(1)
        .trackColor($r('app.color.divider'))
        .selectedColor($r('app.color.accent'))
        .onChange((value: number) => {
          this.settings.textStyle.lineHeight = Math.round(value * 10) / 10;
          this.notifyChange();
        })

      Text(`${this.settings.textStyle.lineHeight.toFixed(1)}`)
        .fontSize(10)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.accent'))
        .width(25)
    }
    .width('100%')

    // 页边距（紧凑）
    Row() {
      Text('边距')
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_primary'))
        .width(30)

      Slider({
        value: this.settings.pageMargins?.left ?? DEFAULT_PAGE_MARGINS.left,
        min: 0,
        max: 80,
        step: 2
      })
        .layoutWeight(1)
        .trackColor($r('app.color.divider'))
        .selectedColor($r('app.color.accent'))
        .onChange((value: number) => {
          this.updateHorizontalMargins(value);
        })

      Text(`${this.settings.pageMargins?.left ?? DEFAULT_PAGE_MARGINS.left}`)
        .fontSize(10)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.accent'))
        .width(32)
    }
    .width('100%')

    Row() {
      Text('上')
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_primary'))
        .width(30)

      Slider({
        value: this.settings.pageMargins?.top ?? DEFAULT_PAGE_MARGINS.top,
        min: 0,
        max: 160,
        step: 2
      })
        .layoutWeight(1)
        .trackColor($r('app.color.divider'))
        .selectedColor($r('app.color.accent'))
        .onChange((value: number) => {
          this.updateTopMargin(value);
        })

      Text(`${this.settings.pageMargins?.top ?? DEFAULT_PAGE_MARGINS.top}`)
        .fontSize(10)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.accent'))
        .width(32)
    }
    .width('100%')

    Row() {
      Text('下')
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_primary'))
        .width(30)

      Slider({
        value: this.settings.pageMargins?.bottom ?? DEFAULT_PAGE_MARGINS.bottom,
        min: 0,
        max: 160,
        step: 2
      })
        .layoutWeight(1)
        .trackColor($r('app.color.divider'))
        .selectedColor($r('app.color.accent'))
        .onChange((value: number) => {
          this.updateBottomMargin(value);
        })

      Text(`${this.settings.pageMargins?.bottom ?? DEFAULT_PAGE_MARGINS.bottom}`)
        .fontSize(10)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.accent'))
        .width(32)
    }
    .width('100%')

    // 文字对齐（紧凑）
    Column() {
      Text('文字对齐')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 6 })

      Row({ space: 4 }) {
        ForEach(
          [
            { text: '左', align: TextAlignment.LEFT },
            { text: '中', align: TextAlignment.CENTER },
            { text: '右', align: TextAlignment.RIGHT },
            { text: '两端', align: TextAlignment.JUSTIFY }
          ],
          (item: AlignmentOption) => {
            Column() {
              Text(item.text)
                .fontSize(10)
                .fontFamily(this.appFontFamily)
                .fontColor(this.settings.textStyle.textAlignment === item.align ?
                  $r('app.color.accent') : $r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .padding(8)
            .backgroundColor(this.settings.textStyle.textAlignment === item.align ?
              $r('app.color.accent_background') : Color.Transparent)
            .borderRadius(6)
            .onClick(() => {
              this.settings.textStyle.textAlignment = item.align;
              this.notifyChange();
            })
          }
        )
      }
      .width('100%')
    }
    .width('100%')

    // 字体粗细（紧凑）
    Column() {
      Text('字体粗细')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 6 })

      Row({ space: 4 }) {
        ForEach(
          [
            { text: '细', weight: 300 },
            { text: '常规', weight: 400 },
            { text: '中', weight: 500 },
            { text: '粗', weight: 700 }
          ],
          (item: WeightOption) => {
            Column() {
              Text(item.text)
                .fontSize(10)
                .fontFamily(this.appFontFamily)
                .fontColor(this.settings.textStyle.fontWeight === item.weight ?
                  $r('app.color.accent') : $r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .padding(8)
            .backgroundColor(this.settings.textStyle.fontWeight === item.weight ?
              $r('app.color.accent_background') : Color.Transparent)
            .borderRadius(6)
            .onClick(() => {
              this.settings.textStyle.fontWeight = item.weight;
              this.notifyChange();
            })
          }
        )
      }
      .width('100%')
    }
    .width('100%')

    // 字体选择（紧凑）
    Row() {
      Text('字体')
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Text(this.getCurrentFontDisplayName())
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.accent'))
    }
    .width('100%')
    .onClick(() => {
      this.showFontPicker = !this.showFontPicker;
    })

    if (this.showFontPicker) {
      Column({ space: 4 }) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.systemFonts, (font: SystemFont) => {
            Text(font.displayName)
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(this.settings.textStyle.fontFamily === font.name ?
                $r('app.color.accent') : $r('app.color.text_secondary'))
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .margin({ right: 4, bottom: 4 })
              .backgroundColor(this.settings.textStyle.fontFamily === font.name ?
                $r('app.color.accent_background') : Color.Transparent)
              .borderRadius(4)
              .onClick(() => {
                this.settings.textStyle.fontFamily = font.name;
                this.settings.textStyle.fontPath = '';
                this.notifyChange();
              })
          }, (font: SystemFont) => font.id)

          ForEach(this.customFonts, (font: CustomFont) => {
            Text(font.displayName)
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(this.settings.textStyle.fontFamily === font.familyName ?
                $r('app.color.accent') : $r('app.color.text_secondary'))
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .margin({ right: 4, bottom: 4 })
              .backgroundColor(this.settings.textStyle.fontFamily === font.familyName ?
                $r('app.color.accent_background') : Color.Transparent)
              .borderRadius(4)
              .onClick(() => {
                this.settings.textStyle.fontFamily = font.familyName;
                this.settings.textStyle.fontPath = font.filePath;
                this.notifyChange();
              })
          }, (font: CustomFont) => font.id)
        }
        .width('100%')
      }
      .width('100%')
      .padding(8)
      .backgroundColor($r('app.color.background_secondary'))
      .borderRadius(6)
    }
  }

  build() {
    if (this.isVisible) {
      Stack() {
        // 背景遮罩
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.background_overlay'))
          .opacity(this.backdropOpacity)
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {
            this.hidePanel();
          })

        if (this.isLandscape) {
          this.buildLandscapePanel()
        } else {
          this.buildPortraitPanel()
        }
      }
      .width('100%')
      .height('100%')
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        const newWidth = Number(newValue.width);
        const newHeight = Number(newValue.height);
        if (newWidth > 0 && newHeight > 0) {
          this.isLandscape = newWidth > newHeight;
        }
      })
      .position({ x: 0, y: 0 })
    }
  }
}
