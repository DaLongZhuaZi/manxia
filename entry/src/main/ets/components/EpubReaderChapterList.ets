import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ThemeManager } from '../Framework/Managers/ThemeManager';
import { EBookChapter } from '../Models/EBookModels';
import { UIContext, display } from '@kit.ArkUI';

const TAG = 'EpubReaderChapterList';

interface EpubChapterListCallbacks {
  onChapterSelect: (spineIndex: number) => void;
  onClose: () => void;
}

@Component
export struct EpubReaderChapterList {
  @Prop chapters: EBookChapter[];
  @Prop currentIndex: number;
  @Prop isVisible: boolean;
  @Prop callbacks: EpubChapterListCallbacks;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  @State private panelOpacity: number = 0;
  @State private panelScale: number = 0.95;
  @State private panelTranslateY: number = 20;
  @State private panelTranslateX: number = -300;
  @State private backdropOpacity: number = 0;
  @State private isLandscape: boolean = false;

  private listScroller: ListScroller = new ListScroller();
  private uiCtx: UIContext | undefined = undefined;

  aboutToAppear(): void {
    this.uiCtx = this.getUIContext();
    this.detectOrientation();
    if (this.isVisible) {
      setTimeout(() => {
        this.showPanel();
        this.scrollToCurrent();
      }, 50);
    }
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

  private scrollToCurrent(): void {
    if (this.currentIndex <= 0 || this.chapters.length === 0) { return; }
    setTimeout(() => {
      try {
        this.listScroller.scrollToIndex(Math.max(0, this.currentIndex - 1), true);
      } catch (e) {
        logger.warn(TAG, `自动滚动失败: ${String(e)}`);
      }
    }, 100);
  }

  private showPanel(): void {
    const ctx = this.uiCtx;
    if (!ctx) { return; }
    ctx.animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.backdropOpacity = 0.5;
    });
    if (this.isLandscape) {
      this.panelTranslateX = -300;
      ctx.animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
        this.panelOpacity = 1;
        this.panelTranslateX = 0;
      });
    } else {
      ctx.animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
        this.panelOpacity = 1;
        this.panelScale = 1;
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
      ctx.animateTo({ duration: 250, curve: Curve.EaseIn, onFinish: () => { this.callbacks.onClose(); } }, () => {
        this.panelOpacity = 0;
        this.panelTranslateX = -300;
      });
    } else {
      ctx.animateTo({ duration: 160, curve: Curve.EaseIn, onFinish: () => { this.callbacks.onClose(); } }, () => {
        this.panelOpacity = 0;
        this.panelScale = 0.95;
        this.panelTranslateY = 20;
      });
    }
    ctx.animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
      this.backdropOpacity = 0;
    });
  }

  private selectChapter(index: number): void {
    this.callbacks.onChapterSelect(index);
    this.hidePanel();
  }

  private getChapterTitle(item: EBookChapter, index: number): string {
    const t = (item.title ?? '').trim();
    return t.length > 0 ? t : `第 ${index + 1} 章`;
  }

  @Builder
  private buildChapterItem(item: EBookChapter, index: number) {
    Row() {
      Text(`${index + 1}`)
        .fontSize(13)
        .fontColor($r('app.color.text_muted'))
        .fontFamily(this.appFontFamily)
        .width(32)
        .textAlign(TextAlign.Center)

      Column() {
        Text(this.getChapterTitle(item, index))
          .fontSize(15)
          .fontWeight(index === this.currentIndex ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(index === this.currentIndex ? $r('app.color.accent_primary') : $r('app.color.text_primary'))
          .fontFamily(this.appFontFamily)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (index === this.currentIndex) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([$r('app.color.accent_primary')])
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(index === this.currentIndex ? $r('app.color.accent_background') : Color.Transparent)
    .borderRadius(8)
    .onClick(() => {
      this.selectChapter(index);
    })
  }

  @Builder
  private buildPortraitPanel() {
    Column() {
      Row() {
        Text('章节目录')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .fontFamily(this.appFontFamily)
          .layoutWeight(1)
        Text(`共${this.chapters.length}章`)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .fontFamily(this.appFontFamily)
          .margin({ right: 12 })
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

      List({ scroller: this.listScroller }) {
        ForEach(this.chapters, (item: EBookChapter, index: number) => {
          ListItem() {
            this.buildChapterItem(item, index)
          }
        })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .divider({ strokeWidth: 0.5, color: $r('app.color.divider_primary'), startMargin: 16, endMargin: 16 })
    }
    .width('90%')
    .height('70%')
    .constraintSize({ maxWidth: 500, maxHeight: 600 })
    .padding(20)
    .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
    .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
    .borderRadius(16)
    .opacity(this.panelOpacity)
    .scale({ x: this.panelScale, y: this.panelScale })
    .translate({ y: this.panelTranslateY })
  }

  @Builder
  private buildLandscapePanel() {
    Row() {
      Column() {
        Row() {
          Text('章节目录')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .fontFamily(this.appFontFamily)
            .layoutWeight(1)
          Text(`共${this.chapters.length}章`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .fontFamily(this.appFontFamily)
            .margin({ right: 8 })
          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(16)
              .fontColor([$r('app.color.text_secondary')])
          }
          .width(32).height(32).backgroundColor(Color.Transparent)
          .onClick(() => { this.hidePanel(); })
        }
        .width('100%')
        .margin({ bottom: 12 })

        List({ scroller: this.listScroller }) {
          ForEach(this.chapters, (item: EBookChapter, index: number) => {
            ListItem() {
              this.buildChapterItem(item, index)
            }
          })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .divider({ strokeWidth: 0.5, color: $r('app.color.divider_primary'), startMargin: 16, endMargin: 16 })
      }
      .width(300).height('100%').padding(16)
      .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
      .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
      .borderRadius({ topRight: 16, bottomRight: 16 })
      .opacity(this.panelOpacity)
      .translate({ x: this.panelTranslateX })
      .hitTestBehavior(HitTestMode.Default)

      Column()
        .layoutWeight(1).height('100%')
        .onClick(() => { this.hidePanel(); })
    }
    .width('100%').height('100%')
  }

  build() {
    if (this.isVisible) {
      Stack() {
        Column()
          .width('100%').height('100%')
          .backgroundColor($r('app.color.background_overlay'))
          .opacity(this.backdropOpacity)
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
