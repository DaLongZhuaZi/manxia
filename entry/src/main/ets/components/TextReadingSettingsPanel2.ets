/**
 * 小说阅读器阅读设置面板
 * 独立对话框，提供阅读模式、翻页动画、开关设置、进度显示等设置
 * 风格与漫画阅读器对话框一致：竖屏底部上滑、横屏右侧滑入
 */

import {
  TextReaderSettings,
  TextReadingMode,
  TextPageTurnAnimation
} from '../Models/TextReaderModels';
import { logger } from '../Utils/Logger';
import { ThemeManager } from '../Framework/Managers/ThemeManager';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeType } from '../Framework/Managers/ThemeManager';
import { curves, UIContext, display } from '@kit.ArkUI';

const TAG = 'TextReadingSettingsPanel2';

/**
 * 翻页动画选项接口
 */
interface AnimationOption {
  text: string;
  anim: TextPageTurnAnimation;
}

/**
 * 回调接口
 */
interface TextReadingSettingsCallbacks {
  onSettingsChange: (settings: TextReaderSettings) => void;
  onClose: () => void;
}

@Component
export struct TextReadingSettingsPanel2 {
  @Prop settings: TextReaderSettings;
  @Prop isVisible: boolean;
  @Prop callbacks: TextReadingSettingsCallbacks;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  // 动画状态
  @State private panelOpacity: number = 0;
  @State private panelTranslateY: number = 300;
  @State private panelTranslateX: number = 320;
  @State private backdropOpacity: number = 0;
  @State private themeState: ThemeAwareState = new ThemeAwareState();
  @State private isLandscape: boolean = false;

  private uiContext: UIContext | undefined = undefined;

  aboutToAppear() {
    this.uiContext = this.getUIContext();
    this.detectScreenOrientation();

    ThemeAwareHelper.initializeThemeAware('TextReadingSettingsPanel2', this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });

    setTimeout(() => {
      this.showPanel();
    }, 50);
  }

  aboutToDisappear() {
    ThemeAwareHelper.cleanupThemeAware('TextReadingSettingsPanel2');
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

  private notifyChange(): void {
    if (this.callbacks.onSettingsChange) {
      this.callbacks.onSettingsChange(this.settings);
    }
  }

  // ==================== 竖屏面板 ====================
  @Builder
  buildPortraitPanel() {
    Column() {
      Row() {
        Text('阅读设置')
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

      Scroll() {
        Column({ space: 20 }) {
          this.buildReadingContent()
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      Row() {
        Button('完成')
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
      Column()
        .layoutWeight(1)
        .height('100%')
        .onClick(() => this.hidePanel())

      Column() {
        Row() {
          Text('阅读设置')
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

        Scroll() {
          Column({ space: 12 }) {
            this.buildReadingContentCompact()
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)

        Button('完成')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_on_accent'))
          .backgroundColor($r('app.color.accent'))
          .width('100%')
          .height(36)
          .onClick(() => this.hidePanel())
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
  buildReadingContent() {
    // 阅读模式
    Column({ space: 12 }) {
      Text('阅读模式')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Row({ space: 8 }) {
        Column() {
          Text('左右翻页')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.settings.readingMode === TextReadingMode.PAGE ?
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(10)
        .backgroundColor(this.settings.readingMode === TextReadingMode.PAGE ?
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => {
          this.settings.readingMode = TextReadingMode.PAGE;
          this.notifyChange();
        })

        Column() {
          Text('上下滚动')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.settings.readingMode === TextReadingMode.SCROLL ?
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(10)
        .backgroundColor(this.settings.readingMode === TextReadingMode.SCROLL ?
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => {
          this.settings.readingMode = TextReadingMode.SCROLL;
          this.notifyChange();
        })

        Column() {
          Text('双页')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.settings.readingMode === TextReadingMode.DUAL_PAGE ?
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(10)
        .backgroundColor(this.settings.readingMode === TextReadingMode.DUAL_PAGE ?
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => {
          this.settings.readingMode = TextReadingMode.DUAL_PAGE;
          this.notifyChange();
        })
      }
      .width('100%')
    }
    .width('100%')

    // 翻页动画（仅在翻页模式或双页模式下显示）
    if (this.settings.readingMode === TextReadingMode.PAGE || this.settings.readingMode === TextReadingMode.DUAL_PAGE) {
      Column({ space: 12 }) {
        Text('翻页动画')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')

        Row({ space: 8 }) {
          ForEach(
            [
              { text: '无', anim: TextPageTurnAnimation.NONE },
              { text: '滑动', anim: TextPageTurnAnimation.SLIDE },
              { text: '卷曲', anim: TextPageTurnAnimation.CURL },
              { text: '淡入', anim: TextPageTurnAnimation.FADE }
            ],
            (item: AnimationOption) => {
              Column() {
                Text(item.text)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.settings.pageTurnAnimation === item.anim ?
                    $r('app.color.accent') : $r('app.color.text_secondary'))
              }
              .layoutWeight(1)
              .padding(10)
              .backgroundColor(this.settings.pageTurnAnimation === item.anim ?
                $r('app.color.accent_background') : Color.Transparent)
              .borderRadius(8)
              .onClick(() => {
                this.settings.pageTurnAnimation = item.anim;
                this.notifyChange();
              })
            }
          )
        }
        .width('100%')
      }
      .width('100%')
    }

    Divider().color($r('app.color.divider'))

    // 开关设置
    this.buildToggleSetting('点击翻页', this.settings.tapToTurn, (isOn: boolean) => {
      this.settings.tapToTurn = isOn;
      this.notifyChange();
    })

    this.buildToggleSetting('音量键翻页', this.settings.volumeKeyNavigation, (isOn: boolean) => {
      this.settings.volumeKeyNavigation = isOn;
      this.notifyChange();
    })

    this.buildToggleSetting('保持屏幕常亮', this.settings.keepScreenOn, (isOn: boolean) => {
      this.settings.keepScreenOn = isOn;
      this.notifyChange();
    })

    Divider().color($r('app.color.divider'))

    // 阅读进度显示
    Column({ space: 8 }) {
      Text('阅读进度显示')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Text('右下角显示信息')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Row({ space: 8 }) {
        Column() {
          Text('页码')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.settings.showPageNumber ?
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(10)
        .backgroundColor(this.settings.showPageNumber ?
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => {
          this.settings.showPageNumber = true;
          this.settings.showProgress = false;
          this.notifyChange();
        })

        Column() {
          Text('进度')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(!this.settings.showPageNumber && this.settings.showProgress ?
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(10)
        .backgroundColor(!this.settings.showPageNumber && this.settings.showProgress ?
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => {
          this.settings.showPageNumber = false;
          this.settings.showProgress = true;
          this.notifyChange();
        })

        Column() {
          Text('不显示')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(!this.settings.showPageNumber && !this.settings.showProgress ?
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(10)
        .backgroundColor(!this.settings.showPageNumber && !this.settings.showProgress ?
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => {
          this.settings.showPageNumber = false;
          this.settings.showProgress = false;
          this.notifyChange();
        })
      }
      .width('100%')
    }
    .width('100%')

    Divider().color($r('app.color.divider'))

    // 其他显示开关
    this.buildToggleSetting('显示时间 (底部中央)', this.settings.showTime, (isOn: boolean) => {
      this.settings.showTime = isOn;
      this.notifyChange();
    })

    this.buildToggleSetting('显示电量 (左下角)', this.settings.showBattery, (isOn: boolean) => {
      this.settings.showBattery = isOn;
      this.notifyChange();
    })
  }

  @Builder
  buildToggleSetting(label: string, isOn: boolean, onChange: (isOn: boolean) => void) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_primary'))
      Blank()
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor($r('app.color.accent'))
        .onChange((value: boolean) => {
          onChange(value);
        })
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  // ==================== 横屏紧凑内容 ====================
  @Builder
  buildReadingContentCompact() {
    // 阅读模式（紧凑）
    Column() {
      Text('阅读模式')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 6 })

      Row({ space: 4 }) {
        Column() {
          Text('翻页')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(this.settings.readingMode === TextReadingMode.PAGE ?
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(8)
        .backgroundColor(this.settings.readingMode === TextReadingMode.PAGE ?
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(6)
        .onClick(() => {
          this.settings.readingMode = TextReadingMode.PAGE;
          this.notifyChange();
        })

        Column() {
          Text('滚动')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(this.settings.readingMode === TextReadingMode.SCROLL ?
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(8)
        .backgroundColor(this.settings.readingMode === TextReadingMode.SCROLL ?
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(6)
        .onClick(() => {
          this.settings.readingMode = TextReadingMode.SCROLL;
          this.notifyChange();
        })

        Column() {
          Text('双页')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(this.settings.readingMode === TextReadingMode.DUAL_PAGE ?
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(8)
        .backgroundColor(this.settings.readingMode === TextReadingMode.DUAL_PAGE ?
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(6)
        .onClick(() => {
          this.settings.readingMode = TextReadingMode.DUAL_PAGE;
          this.notifyChange();
        })
      }
      .width('100%')
    }
    .width('100%')

    // 翻页动画（紧凑）
    if (this.settings.readingMode === TextReadingMode.PAGE || this.settings.readingMode === TextReadingMode.DUAL_PAGE) {
      Column() {
        Text('翻页动画')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .margin({ bottom: 6 })

        Row({ space: 4 }) {
          ForEach(
            [
              { text: '无', anim: TextPageTurnAnimation.NONE },
              { text: '滑动', anim: TextPageTurnAnimation.SLIDE },
              { text: '卷曲', anim: TextPageTurnAnimation.CURL },
              { text: '淡入', anim: TextPageTurnAnimation.FADE }
            ],
            (item: AnimationOption) => {
              Column() {
                Text(item.text)
                  .fontSize(10)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.settings.pageTurnAnimation === item.anim ?
                    $r('app.color.accent') : $r('app.color.text_secondary'))
              }
              .layoutWeight(1)
              .padding(8)
              .backgroundColor(this.settings.pageTurnAnimation === item.anim ?
                $r('app.color.accent_background') : Color.Transparent)
              .borderRadius(6)
              .onClick(() => {
                this.settings.pageTurnAnimation = item.anim;
                this.notifyChange();
              })
            }
          )
        }
        .width('100%')
      }
      .width('100%')
    }

    Divider().color($r('app.color.divider'))

    // 开关设置（紧凑两列）
    Column() {
      Text('其他设置')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 6 })

      Row() {
        Column() {
          Row() {
            Text('点击翻页')
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.settings.tapToTurn })
              .selectedColor($r('app.color.accent'))
              .onChange((isOn: boolean) => {
                this.settings.tapToTurn = isOn;
                this.notifyChange();
              })
          }
          .width('100%')
          .margin({ bottom: 6 })

          Row() {
            Text('屏幕常亮')
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.settings.keepScreenOn })
              .selectedColor($r('app.color.accent'))
              .onChange((isOn: boolean) => {
                this.settings.keepScreenOn = isOn;
                this.notifyChange();
              })
          }
          .width('100%')
          .margin({ bottom: 6 })

          Row() {
            Text('显示时间')
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.settings.showTime })
              .selectedColor($r('app.color.accent'))
              .onChange((isOn: boolean) => {
                this.settings.showTime = isOn;
                this.notifyChange();
              })
          }
          .width('100%')
        }
        .layoutWeight(1)
        .margin({ right: 8 })

        Column() {
          Row() {
            Text('音量翻页')
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.settings.volumeKeyNavigation })
              .selectedColor($r('app.color.accent'))
              .onChange((isOn: boolean) => {
                this.settings.volumeKeyNavigation = isOn;
                this.notifyChange();
              })
          }
          .width('100%')
          .margin({ bottom: 6 })

          Row() {
            Text('显示电量')
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.settings.showBattery })
              .selectedColor($r('app.color.accent'))
              .onChange((isOn: boolean) => {
                this.settings.showBattery = isOn;
                this.notifyChange();
              })
          }
          .width('100%')
        }
        .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')

    Divider().color($r('app.color.divider'))

    // 进度显示（紧凑）
    Column() {
      Text('右下角显示')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 6 })

      Row({ space: 4 }) {
        Column() {
          Text('页码')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(this.settings.showPageNumber ?
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(8)
        .backgroundColor(this.settings.showPageNumber ?
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(6)
        .onClick(() => {
          this.settings.showPageNumber = true;
          this.settings.showProgress = false;
          this.notifyChange();
        })

        Column() {
          Text('进度')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(!this.settings.showPageNumber && this.settings.showProgress ?
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(8)
        .backgroundColor(!this.settings.showPageNumber && this.settings.showProgress ?
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(6)
        .onClick(() => {
          this.settings.showPageNumber = false;
          this.settings.showProgress = true;
          this.notifyChange();
        })

        Column() {
          Text('无')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(!this.settings.showPageNumber && !this.settings.showProgress ?
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(8)
        .backgroundColor(!this.settings.showPageNumber && !this.settings.showProgress ?
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(6)
        .onClick(() => {
          this.settings.showPageNumber = false;
          this.settings.showProgress = false;
          this.notifyChange();
        })
      }
      .width('100%')
    }
    .width('100%')
  }

  build() {
    if (this.isVisible) {
      Stack() {
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
