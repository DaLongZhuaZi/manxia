import os

file_path = 'F:/DevEcoStudioProject/manxia/entry/src/main/ets/pages/SourceDetailPage.ets'

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Fix search dialog breakage
bad_dialog = """        Row({ space: 12 }) {
          Button('取消')
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .onClick(() => {
              this.performSearch();
            })
        }"""

good_dialog = """        Row({ space: 12 }) {
          Button('取消')
            .fontSize(15)
            .layoutWeight(1)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .onClick(() => {
              this.showSearchDialog = false;
            })

          Button('搜索')
            .fontSize(15)
            .layoutWeight(1)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .onClick(() => {
              this.performSearch();
            })
        }"""

content = content.replace(bad_dialog, good_dialog)

# Add 已添加 label to buildReadingStyleComicCover
target_cover_end = """        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')"""

replacement_cover_end = """        .hitTestBehavior(HitTestMode.None)
      }

      // 已添加书库标签
      if (this.addedComicIds[comic.id]) {
        Row() {
          Text('已添加')
            .fontSize(10)
            .fontColor(Color.White)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + 'E6')
            .padding({ left: 4, right: 4, top: 2, bottom: 2 })
            .borderRadius({ topRight: 6 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Start)
        .alignItems(VerticalAlign.Bottom)
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')"""

# We only replace the first occurrence if multiple, but here it's fine
if replacement_cover_end not in content:
    content = content.replace(target_cover_end, replacement_cover_end, 1)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
