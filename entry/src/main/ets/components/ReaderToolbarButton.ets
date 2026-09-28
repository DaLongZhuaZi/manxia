/**
 * 阅读器工具栏/顶栏通用按钮：图标 + 可开关的文字提示。
 * 文字提示由全局设置 reader_toolbar_text_hint_enabled 控制（默认开启），
 * 开关切换后所有已打开的阅读器通过 AppStorage 实时刷新。
 * 为保证各阅读器工具栏高度不变，文字与图标叠放在原有的 48x48 按钮区域内。
 */
@Component
export struct ReaderToolbarButton {
  @Prop icon: Resource;
  @Prop label: string;
  @Prop iconColor: ResourceColor;
  @Prop iconSize: number = 20;
  @Prop buttonWidth: number = 48;
  @Prop buttonHeight: number = 48;
  @Prop labelFontSize: number = 9;
  onAction: () => void = () => {};
  @StorageProp('reader_toolbar_text_hint_enabled') showTextHint: boolean = true;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  build() {
    Button() {
      Column({ space: 1 }) {
        SymbolGlyph(this.icon)
          .fontSize(this.showTextHint ? this.iconSize : this.iconSize + 2)
          .fontColor([this.iconColor])
        if (this.showTextHint) {
          Text(this.label)
            .fontSize(this.labelFontSize)
            .fontColor(this.iconColor)
            .fontFamily(this.appFontFamily)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
            .width('100%')
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width(this.buttonWidth)
    .height(this.buttonHeight)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      this.onAction();
    })
  }
}

/**
 * 阅读器工具栏/顶栏通用按钮（图片图标版）：Image 图标 + 可开关的文字提示。
 * 供仍使用 app.media 图标的阅读器（如 components/EBookReaderPage）使用。
 */
@Component
export struct ReaderToolbarImageButton {
  @Prop icon: Resource;
  @Prop label: string;
  @Prop fillColor: ResourceColor;
  @Prop iconSize: number = 24;
  @Prop buttonWidth: number = 48;
  @Prop buttonHeight: number = 48;
  @Prop labelFontSize: number = 9;
  onAction: () => void = () => {};
  @StorageProp('reader_toolbar_text_hint_enabled') showTextHint: boolean = true;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  build() {
    Button() {
      Column({ space: 1 }) {
        Image(this.icon)
          .width(this.showTextHint ? this.iconSize : this.iconSize + 2)
          .height(this.showTextHint ? this.iconSize : this.iconSize + 2)
          .fillColor(this.fillColor)
        if (this.showTextHint) {
          Text(this.label)
            .fontSize(this.labelFontSize)
            .fontColor(this.fillColor)
            .fontFamily(this.appFontFamily)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
            .width('100%')
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width(this.buttonWidth)
    .height(this.buttonHeight)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      this.onAction();
    })
  }
}
