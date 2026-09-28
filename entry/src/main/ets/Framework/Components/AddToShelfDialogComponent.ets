/**
 * 添加到书架对话框组件
 * 从 UnifiedDetailPage 提取，用于选择要添加到的书架
 */

import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { SourceDialogScaffold } from './SourceDialogScaffold';
import { TypeShelf, ShelfType, ShelfContentType } from '../Data/TypeShelfManager';

@Component
export struct AddToShelfDialogComponent {
  @Prop themeState: ThemeAwareState = new ThemeAwareState();
  @Prop @Watch('onLoadSignalChanged') loadSignal: number = 0;
  @Prop shelves: TypeShelf[] = [];
  @Prop isPending: boolean = false;
  onShelfSelected?: (shelf: TypeShelf) => void;
  onFavoriteOnly?: () => void;
  onCancel?: () => void;

  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State isVisible: boolean = false;

  private lastSignal: number = 0;

  onLoadSignalChanged(): void {
    if (this.loadSignal > this.lastSignal) {
      this.lastSignal = this.loadSignal;
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
        this.isVisible = true;
      });
    }
  }

  private hideDialog(): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseIn }, () => {
      this.isVisible = false;
    });
  }

  build() {
    if (this.isVisible) {
      SourceDialogScaffold({
        themeState: this.themeState,
        onMaskTap: () => {
          this.hideDialog();
          this.onCancel?.();
        },
        dialogWidth: '90%',
        maxWidth: 360,
        contentPadding: 24,
        useMaskBlur: true
      }) {
        Column({ space: 20 }) {
            // 标题栏
            Row() {
              Text('添加到书架')
                .fontSize(20)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

              Blank()

              Button() {
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(18)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
              }
              .width(32)
              .height(32)
              .backgroundColor(Color.Transparent)
              .enabled(!this.isPending)
              .onClick(() => {
                this.hideDialog();
                this.onCancel?.();
              })
            }
            .width('100%')

            // 书架列表
            List({ space: 8 }) {
              // 默认书架选项
              ListItem() {
                Row({ space: 12 }) {
                  Column() {
                    SymbolGlyph($r('sys.symbol.bookshelf'))
                      .fontSize(24)
                      .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
                  }
                  .width(44)
                  .height(44)
                  .justifyContent(FlexAlign.Center)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15')
                  .borderRadius(10)

                  Column({ space: 4 }) {
                    Text('默认书架')
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

                    Text('仅收藏到默认书库，不添加到自定义书架')
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(16)
                    .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme)])
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                .borderRadius(12)
                .onClick(() => {
                  if (this.isPending) return;
                  this.hideDialog();
                  this.onFavoriteOnly?.();
                })
              }

              // 自定义书架列表
              ForEach(this.shelves, (shelf: TypeShelf) => {
                ListItem() {
                  Row({ space: 12 }) {
                    Column() {
                      SymbolGlyph($r('sys.symbol.bookshelf'))
                        .fontSize(24)
                        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
                    }
                    .width(44)
                    .height(44)
                    .justifyContent(FlexAlign.Center)
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15')
                    .borderRadius(10)

                    Column({ space: 4 }) {
                      Text(shelf.name)
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

                      Text(shelf.shelfType === ShelfType.MIXED ? '混合书架' :
                        shelf.shelfType === ShelfType.DYNAMIC ? '动态书架' :
                          shelf.contentTypes.includes(ShelfContentType.MANGA) ? '漫画' :
                            shelf.contentTypes.includes(ShelfContentType.EBOOK) ? '电子书' : '小说')
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    SymbolGlyph($r('sys.symbol.chevron_right'))
                      .fontSize(16)
                      .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme)])
                  }
                  .width('100%')
                  .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                  .borderRadius(12)
                  .onClick(() => {
                    if (this.isPending) return;
                    this.hideDialog();
                    this.onShelfSelected?.(shelf);
                  })
                }
              }, (shelf: TypeShelf) => shelf.id)
            }
            .width('100%')
            .constraintSize({ maxHeight: 300 })
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
          }
          .width('100%')
      }
    }
  }
}
