import { ThemeManager } from '../Framework/Managers/ThemeManager';
import {
  EBookReadingSettings,
  DEFAULT_EBOOK_READING_SETTINGS,
  EBOOK_THEME_PRESETS,
  EBookThemePreset
} from '../Models/EBookModels';
import { UIContext, display } from '@kit.ArkUI';

interface EpubSettingsPanelCallbacks {
  onSettingsChange: (settings: EBookReadingSettings) => void;
  onClose: () => void;
}

@Component
export struct EpubReaderSettingsPanel {
  @Prop settings: EBookReadingSettings;
  @Prop isVisible: boolean;
  @Prop callbacks: EpubSettingsPanelCallbacks;

  @State private current: EBookReadingSettings = {
    fontSize: DEFAULT_EBOOK_READING_SETTINGS.fontSize,
    fontFamily: DEFAULT_EBOOK_READING_SETTINGS.fontFamily,
    fontPath: DEFAULT_EBOOK_READING_SETTINGS.fontPath,
    fontWeight: DEFAULT_EBOOK_READING_SETTINGS.fontWeight,
    lineHeight: DEFAULT_EBOOK_READING_SETTINGS.lineHeight,
    backgroundColor: DEFAULT_EBOOK_READING_SETTINGS.backgroundColor,
    textColor: DEFAULT_EBOOK_READING_SETTINGS.textColor,
    themeBgImage: DEFAULT_EBOOK_READING_SETTINGS.themeBgImage,
    nightMode: DEFAULT_EBOOK_READING_SETTINGS.nightMode,
    followSystemTheme: DEFAULT_EBOOK_READING_SETTINGS.followSystemTheme,
    pageMargin: DEFAULT_EBOOK_READING_SETTINGS.pageMargin,
    pageMode: DEFAULT_EBOOK_READING_SETTINGS.pageMode,
    brightness: DEFAULT_EBOOK_READING_SETTINGS.brightness,
    autoSave: DEFAULT_EBOOK_READING_SETTINGS.autoSave,
    saveInterval: DEFAULT_EBOOK_READING_SETTINGS.saveInterval,
    letterSpacing: 0,
    paragraphSpacing: 8,
    firstLineIndent: 2,
    textAlignment: 'JUSTIFY',
    pageTurnAnimation: 'SLIDE',
    tapToTurn: true,
    volumeKeyNavigation: true,
    keepScreenOn: false,
    showPageNumber: true,
    showProgress: false,
    showTime: true,
    showBattery: false,
    backgroundType: 'COLOR',
    backgroundImagePath: '',
    backgroundImageOpacity: 0.3
  };

  @State private panelOpacity: number = 0;
  @State private panelTranslateY: number = 300;
  @State private panelTranslateX: number = 320;
  @State private backdropOpacity: number = 0;
  @State private isLandscape: boolean = false;

  private uiCtx: UIContext | undefined = undefined;

  aboutToAppear(): void {
    this.uiCtx = this.getUIContext();
    this.syncSettings();
    this.detectOrientation();
    if (this.isVisible) {
      setTimeout(() => { this.showPanel(); }, 50);
    }
  }

  private syncSettings(): void {
    this.current.fontSize = this.settings.fontSize;
    this.current.fontFamily = this.settings.fontFamily;
    this.current.fontPath = this.settings.fontPath;
    this.current.fontWeight = this.settings.fontWeight;
    this.current.lineHeight = this.settings.lineHeight;
    this.current.backgroundColor = this.settings.backgroundColor;
    this.current.textColor = this.settings.textColor;
    this.current.themeBgImage = this.settings.themeBgImage;
    this.current.nightMode = this.settings.nightMode;
    this.current.followSystemTheme = this.settings.followSystemTheme;
    this.current.pageMargin = this.settings.pageMargin;
    this.current.pageMode = this.settings.pageMode;
    this.current.brightness = this.settings.brightness;
    this.current.autoSave = this.settings.autoSave;
    this.current.saveInterval = this.settings.saveInterval;
    this.current.letterSpacing = this.settings.letterSpacing ?? 0;
    this.current.paragraphSpacing = this.settings.paragraphSpacing ?? 8;
    this.current.firstLineIndent = this.settings.firstLineIndent ?? 2;
    this.current.textAlignment = this.settings.textAlignment ?? 'JUSTIFY';
    this.current.pageTurnAnimation = this.settings.pageTurnAnimation ?? 'SLIDE';
    this.current.tapToTurn = this.settings.tapToTurn ?? true;
    this.current.volumeKeyNavigation = this.settings.volumeKeyNavigation ?? true;
    this.current.keepScreenOn = this.settings.keepScreenOn ?? false;
    this.current.showPageNumber = this.settings.showPageNumber ?? true;
    this.current.showProgress = this.settings.showProgress ?? false;
    this.current.showTime = this.settings.showTime ?? true;
    this.current.showBattery = this.settings.showBattery ?? false;
    this.current.backgroundType = this.settings.backgroundType ?? 'COLOR';
    this.current.backgroundImagePath = this.settings.backgroundImagePath ?? '';
    this.current.backgroundImageOpacity = this.settings.backgroundImageOpacity ?? 0.3;
  }

  private detectOrientation(): void {
    try {
      const d = display.getDefaultDisplaySync();
      const w = d.width / (d.densityPixels || 1);
      const h = d.height / (d.densityPixels || 1);
      this.isLandscape = w > h;
    } catch (e) {
      this.isLandscape = false;
    }
  }

  private showPanel(): void {
    const ctx = this.uiCtx;
    if (!ctx) { return; }
    ctx.animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.backdropOpacity = 0.5;
    });
    if (this.isLandscape) {
      this.panelTranslateX = 320;
      ctx.animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
        this.panelOpacity = 1;
        this.panelTranslateX = 0;
      });
    } else {
      this.panelTranslateY = 300;
      ctx.animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
        this.panelOpacity = 1;
        this.panelTranslateY = 0;
      });
    }
  }

  private hidePanel(): void {
    const ctx = this.uiCtx;
    if (!ctx) {
      this.callbacks.onClose();
      return;
    }
    if (this.isLandscape) {
      ctx.animateTo({ duration: 200, curve: Curve.EaseIn, onFinish: () => { this.callbacks.onClose(); } }, () => {
        this.panelOpacity = 0;
        this.panelTranslateX = 320;
      });
    } else {
      ctx.animateTo({ duration: 250, curve: Curve.EaseInOut, onFinish: () => { this.callbacks.onClose(); } }, () => {
        this.panelOpacity = 0;
        this.panelTranslateY = 300;
      });
    }
    ctx.animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
      this.backdropOpacity = 0;
    });
  }

  private notify(): void {
    this.callbacks.onSettingsChange(this.current);
  }

  private applyThemePreset(preset: EBookThemePreset): void {
    this.current.backgroundColor = preset.backgroundColor;
    this.current.textColor = preset.textColor;
    this.current.nightMode = preset.nightMode;
    this.current.followSystemTheme = false;
    this.notify();
  }

  private isPresetActive(preset: EBookThemePreset): boolean {
    return this.current.backgroundColor === preset.backgroundColor &&
      this.current.textColor === preset.textColor;
  }

  @Builder
  private buildThemePresets() {
    Column() {
      Text('阅读主题')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 12 })

      Row({ space: 8 }) {
        ForEach(EBOOK_THEME_PRESETS, (preset: EBookThemePreset) => {
          Column() {
            Column()
              .width(36)
              .height(36)
              .borderRadius(8)
              .backgroundColor(preset.backgroundColor)
              .border({
                width: this.isPresetActive(preset) ? 2 : 1,
                color: this.isPresetActive(preset) ? $r('app.color.accent_primary') : $r('app.color.divider_primary')
              })
            Text(preset.name)
              .fontSize(11)
              .fontColor(this.isPresetActive(preset) ? $r('app.color.accent_primary') : $r('app.color.text_secondary'))
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Center)
          .layoutWeight(1)
          .onClick(() => { this.applyThemePreset(preset); })
        })
      }
      .width('100%')
    }
    .width('100%')
    .margin({ bottom: 20 })
  }

  @Builder
  private buildFontSizeControl() {
    Column() {
      Row() {
        Text('字体大小')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(`${Math.round(this.current.fontSize)}`)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .margin({ bottom: 8 })

      Row({ space: 12 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.minus'))
            .fontSize(18)
            .fontColor([$r('app.color.text_primary')])
        }
        .width(40).height(40).backgroundColor($r('app.color.background_secondary')).borderRadius(8)
        .onClick(() => {
          this.current.fontSize = Math.max(12, this.current.fontSize - 1);
          this.notify();
        })

        Slider({ value: this.current.fontSize, min: 12, max: 36, step: 1 })
          .layoutWeight(1)
          .trackColor($r('app.color.divider_primary'))
          .selectedColor($r('app.color.accent_primary'))
          .onChange((value: number) => {
            this.current.fontSize = Math.round(value);
            this.notify();
          })

        Button() {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(18)
            .fontColor([$r('app.color.text_primary')])
        }
        .width(40).height(40).backgroundColor($r('app.color.background_secondary')).borderRadius(8)
        .onClick(() => {
          this.current.fontSize = Math.min(36, this.current.fontSize + 1);
          this.notify();
        })
      }
      .width('100%')
    }
    .width('100%')
    .margin({ bottom: 20 })
  }

  @Builder
  private buildLineHeightControl() {
    Column() {
      Row() {
        Text('行间距')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(`${this.current.lineHeight.toFixed(1)}`)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .margin({ bottom: 8 })

      Slider({ value: this.current.lineHeight, min: 1.0, max: 3.0, step: 0.1 })
        .width('100%')
        .trackColor($r('app.color.divider_primary'))
        .selectedColor($r('app.color.accent_primary'))
        .onChange((value: number) => {
          this.current.lineHeight = Math.round(value * 10) / 10;
          this.notify();
        })
    }
    .width('100%')
    .margin({ bottom: 20 })
  }

  @Builder
  private buildMarginControl() {
    Column() {
      Row() {
        Text('页面边距')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(`${Math.round(this.current.pageMargin)}`)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .margin({ bottom: 8 })

      Slider({ value: this.current.pageMargin, min: 0, max: 48, step: 2 })
        .width('100%')
        .trackColor($r('app.color.divider_primary'))
        .selectedColor($r('app.color.accent_primary'))
        .onChange((value: number) => {
          this.current.pageMargin = Math.round(value / 2) * 2;
          this.notify();
        })
    }
    .width('100%')
    .margin({ bottom: 20 })
  }

  @Builder
  private buildFontWeightControl() {
    Row() {
      Text('字体粗细')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Blank()
      Row({ space: 8 }) {
        Text('常规')
          .fontSize(13)
          .fontColor(this.current.fontWeight <= 400 ? $r('app.color.accent_primary') : $r('app.color.text_secondary'))
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor(this.current.fontWeight <= 400 ? $r('app.color.accent_background') : $r('app.color.background_secondary'))
          .borderRadius(6)
          .onClick(() => {
            this.current.fontWeight = 400;
            this.notify();
          })
        Text('加粗')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.current.fontWeight > 400 ? $r('app.color.accent_primary') : $r('app.color.text_secondary'))
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor(this.current.fontWeight > 400 ? $r('app.color.accent_background') : $r('app.color.background_secondary'))
          .borderRadius(6)
          .onClick(() => {
            this.current.fontWeight = 700;
            this.notify();
          })
      }
    }
    .width('100%')
    .margin({ bottom: 20 })
  }

  @Builder
  private buildPortraitPanel() {
    Column() {
      Blank()
      Column() {
        Row() {
          Text('阅读设置')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(18)
              .fontColor([$r('app.color.text_secondary')])
          }
          .width(36).height(36).backgroundColor(Color.Transparent)
          .onClick(() => { this.hidePanel(); })
        }
        .width('100%')
        .margin({ bottom: 20 })

        Scroll() {
          Column() {
            this.buildThemePresets()
            Divider().color($r('app.color.divider_primary')).margin({ bottom: 20 })
            this.buildFontSizeControl()
            this.buildLineHeightControl()
            this.buildMarginControl()
            this.buildFontWeightControl()
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Off)

        Row({ space: 12 }) {
          Button('恢复默认')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .backgroundColor($r('app.color.background_secondary'))
            .layoutWeight(1).height(44)
            .onClick(() => {
              this.current.fontSize = DEFAULT_EBOOK_READING_SETTINGS.fontSize;
              this.current.lineHeight = DEFAULT_EBOOK_READING_SETTINGS.lineHeight;
              this.current.pageMargin = DEFAULT_EBOOK_READING_SETTINGS.pageMargin;
              this.current.fontWeight = DEFAULT_EBOOK_READING_SETTINGS.fontWeight;
              this.current.backgroundColor = DEFAULT_EBOOK_READING_SETTINGS.backgroundColor;
              this.current.textColor = DEFAULT_EBOOK_READING_SETTINGS.textColor;
              this.current.nightMode = DEFAULT_EBOOK_READING_SETTINGS.nightMode;
              this.current.followSystemTheme = DEFAULT_EBOOK_READING_SETTINGS.followSystemTheme;
              this.notify();
            })
          Button('关闭')
            .fontSize(14)
            .fontColor($r('app.color.text_on_accent'))
            .backgroundColor($r('app.color.accent_primary'))
            .layoutWeight(1).height(44)
            .onClick(() => { this.hidePanel(); })
        }
        .width('100%')
        .margin({ top: 16 })
      }
      .width('100%')
      .height('80%')
      .padding(20)
      .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
      .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
      .borderRadius({ topLeft: 16, topRight: 16 })
      .opacity(this.panelOpacity)
      .translate({ x: 0, y: this.panelTranslateY })
      .hitTestBehavior(HitTestMode.Default)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
  }

  @Builder
  private buildLandscapePanel() {
    Row() {
      Column()
        .layoutWeight(1)
        .height('100%')
        .onClick(() => { this.hidePanel(); })

      Column() {
        Row() {
          Text('阅读设置')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(18)
              .fontColor([$r('app.color.text_secondary')])
          }
          .width(36).height(36).backgroundColor(Color.Transparent)
          .onClick(() => { this.hidePanel(); })
        }
        .width('100%')
        .margin({ bottom: 16 })

        Scroll() {
          Column() {
            this.buildThemePresets()
            Divider().color($r('app.color.divider_primary')).margin({ bottom: 16 })
            this.buildFontSizeControl()
            this.buildLineHeightControl()
            this.buildMarginControl()
            this.buildFontWeightControl()
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Off)

        Row({ space: 8 }) {
          Button('恢复默认')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .backgroundColor($r('app.color.background_secondary'))
            .layoutWeight(1).height(40)
            .onClick(() => {
              this.current.fontSize = DEFAULT_EBOOK_READING_SETTINGS.fontSize;
              this.current.lineHeight = DEFAULT_EBOOK_READING_SETTINGS.lineHeight;
              this.current.pageMargin = DEFAULT_EBOOK_READING_SETTINGS.pageMargin;
              this.current.fontWeight = DEFAULT_EBOOK_READING_SETTINGS.fontWeight;
              this.current.backgroundColor = DEFAULT_EBOOK_READING_SETTINGS.backgroundColor;
              this.current.textColor = DEFAULT_EBOOK_READING_SETTINGS.textColor;
              this.current.nightMode = DEFAULT_EBOOK_READING_SETTINGS.nightMode;
              this.current.followSystemTheme = DEFAULT_EBOOK_READING_SETTINGS.followSystemTheme;
              this.notify();
            })
          Button('关闭')
            .fontSize(13)
            .fontColor($r('app.color.text_on_accent'))
            .backgroundColor($r('app.color.accent_primary'))
            .layoutWeight(1).height(40)
            .onClick(() => { this.hidePanel(); })
        }
        .width('100%')
        .margin({ top: 12 })
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

  build() {
    if (this.isVisible) {
      Stack() {
        Column()
          .width('100%').height('100%')
          .backgroundColor($r('app.color.background_overlay'))
          .opacity(this.backdropOpacity)
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => { this.hidePanel(); })

        if (this.isLandscape) {
          this.buildLandscapePanel()
        } else {
          this.buildPortraitPanel()
        }
      }
      .width('100%').height('100%')
      .position({ x: 0, y: 0 })
      .onAreaChange((_old: Area, newVal: Area) => {
        const w = Number(newVal.width);
        const h = Number(newVal.height);
        if (w > 0 && h > 0) {
          this.isLandscape = w > h;
        }
      })
    }
  }
}
