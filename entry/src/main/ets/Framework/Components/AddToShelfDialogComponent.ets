/**
 * 添加到书架对话框组件
 * 从 UnifiedDetailPage 提取，用于选择要添加到的书架
 */

import { ThemeAwareState, ThemeAwareHelper } from './ThemeAware';
import { SourceDialogScaffold } from './SourceDialogScaffold';
import { DialogSurfaceStyleHelper } from './DialogSurfaceStyleHelper';
import { DialogAnimationState } from '../../Utils/DialogAnimationState';
import { ThemeType } from '../Managers/ThemeManager';
import { TypeShelf, ShelfType, ShelfContentType } from '../Data/TypeShelfManager';

@Component
export struct AddToShelfDialogComponent {
  @Prop themeState!: ThemeAwareState;
  @Prop @Watch('onLoadSignalChanged') loadSignal: number = 0;
  @Prop shelves: TypeShelf[] = [];
  @Prop isPending: boolean = false;
  onShelfSelected?: (shelf: TypeShelf) => void;
  onFavoriteOnly?: () => void;
  onCancel?: () => void;

  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State isVisible: boolean = false;
  @State anim: DialogAnimationState = new DialogAnimationState({ initialScale: 0.8, initialTranslateY: 0 });

  private lastSignal: number = 0;

  onLoadSignalChanged(): void {
    if (this.loadSignal > this.lastSignal) {
      this.lastSignal = this.loadSignal;
      this.isVisible = true;
      this.anim.animateIn(this.getUIContext());
    }
  }

  private hideDialog(): void {
    this.anim.animateOut(this.getUIContext(), () => {
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
        contentPadding: 0,
        dialogRadius: 26,
        zIndexValue: 120,
        useMaskBlur: true,
        maskBlurStyle: DialogSurfaceStyleHelper.getPopupMaskBlurStyle(),
        maskColor: DialogSurfaceStyleHelper.getPopupMaskColor()
      }) {
        Stack({ alignContent: Alignment.TopStart }) {
          // dialog chrome
          Column()
            .width('100%')
            .height(1)
            .backgroundColor(this.themeState.currentTheme === ThemeType.DARK
              ? 'rgba(255, 255, 255, 0.18)'
              : 'rgba(255, 255, 255, 0.58)')
          Column()
            .width('100%')
            .height(1)
            .align(Alignment.Bottom)
            .backgroundColor(this.themeState.currentTheme === ThemeType.DARK
              ? 'rgba(154, 196, 255, 0.08)'
              : 'rgba(126, 166, 220, 0.10)')

          Column({ space: 16 }) {
            // 标题栏
            Row() {
              Text('添加到书架')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
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
                    SymbolGlyph($r('sys.symbol.books_vertical_fill'))
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
                      SymbolGlyph($r('sys.symbol.books_vertical_fill'))
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
          .padding(20)
          .scale({ x: this.anim.scale, y: this.anim.scale })
          .opacity(this.anim.opacity)
          .borderRadius(26)
          .clip(true)
          .onClick(() => {})
        }
      }
    }
  }
}
