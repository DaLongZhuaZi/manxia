$path = 'entry/src/main/ets/pages/MainMenuPage.ets'
$text = [System.IO.File]::ReadAllText($path)

$replacement = @'
  @Builder
  buildCategoryView() {
    Column() {
      Scroll() {
        Grid() {
          if (this.mangaList.length > 0) {
            GridItem() {
              this.buildTypeShelfCard(LibraryContentType.MANGA, '漫画书架', this.mangaList.length, this.getMangaShelfCovers())
            }
          }

          if (this.ebookList.length > 0 || this.pdfEbookList.length > 0) {
            GridItem() {
              this.buildTypeShelfCard(LibraryContentType.EBOOK, '电子书书架', this.ebookList.length + this.pdfEbookList.length, this.getEBookShelfCovers())
            }
          }

          if (this.novelList.length > 0) {
            GridItem() {
              this.buildTypeShelfCard(LibraryContentType.NOVEL, '小说书架', this.novelList.length, this.getNovelShelfCovers())
            }
          }

          ForEach(this.typeShelves.filter((shelf: TypeShelf) => {
            if (shelf.isSystem) return false;
            if (this.contentFilterManager.isSFWModeEnabled() &&
              shelf.shelfType === ShelfType.DYNAMIC &&
              shelf.dynamicFilter !== undefined &&
              shelf.dynamicFilter.nsfwFilter === 'nsfw') {
              return false;
            }
            return true;
          }), (shelf: TypeShelf) => {
            GridItem() {
              this.buildCustomShelfCard(shelf)
            }
            .scale({ x: this.deletingShelfId === shelf.id ? 0 : 1, y: this.deletingShelfId === shelf.id ? 0 : 1 })
            .opacity(this.deletingShelfId === shelf.id ? 0 : 1)
            .animation({ duration: 300, curve: Curve.EaseIn })
          }, (shelf: TypeShelf) => shelf.id)

          GridItem() {
            this.buildAddShelfCard()
          }
          .scale({ x: this.shelfCardAnimationScale, y: this.shelfCardAnimationScale })
          .animation({ duration: 300, curve: Curve.EaseOut })

          if (this.mangaList.length === 0 && this.ebookList.length === 0 && this.pdfEbookList.length === 0 && this.novelList.length === 0 && this.typeShelves.filter((s: TypeShelf) => !s.isSystem).length === 0) {
            GridItem() {
              this.buildTypeShelfCard(LibraryContentType.MANGA, '默认书架', 0, [])
            }
          }
        }
        .columnsTemplate(this.getShelfGridColumnsTemplate())
        .rowsGap(this.responsive_gridGap)
        .columnsGap(this.responsive_gridGap)
        .width('100%')
        .padding({
          left: this.responsive_contentPadding,
          right: this.responsive_contentPadding,
          top: 4,
          bottom: this.getMainTabBottomSpacerHeight()
        })
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .friction(0.6)
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
  }

'@

$pattern = '(?s)@Builder\s+buildCategoryView\(\)\s*\{.*?\n  \}\r?\n\r?\n  /\*\*'
if (-not [regex]::IsMatch($text, $pattern)) { throw 'buildCategoryView not found' }
$text = [regex]::Replace($text, $pattern, $replacement + '  /**', 1)
[System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
