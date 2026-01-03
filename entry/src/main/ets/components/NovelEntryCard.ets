/**
 * 小说模块入口卡片组件
 * 用于在主页展示小说入口
 * 
 * 文件路径: entry/src/main/ets/components/NovelEntryCard.ets
 */

import { router } from '@kit.ArkUI';

@Component
export struct NovelEntryCard {
  @Prop recentCount: number = 0;
  @Prop favoriteCount: number = 0;

  build() {
    Column() {
      Row() {
        Column() {
          Text('📚')
            .fontSize(32)
        }
        .width(56)
        .height(56)
        .borderRadius(12)
        .backgroundColor('#E6F7FF')
        .justifyContent(FlexAlign.Center)
        
        Column() {
          Text('小说阅读')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#333333')
          
          Text('支持Legado书源')
            .fontSize(12)
            .fontColor('#999999')
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 })
        .layoutWeight(1)
        
        SymbolGlyph($r('sys.symbol.arrow_right'))
          .fontSize(20)
          .fontColor(['#CCCCCC'])
      }
      .width('100%')
      
      // 统计信息
      if (this.recentCount > 0 || this.favoriteCount > 0) {
        Row() {
          if (this.favoriteCount > 0) {
            Row() {
              Text('❤️')
                .fontSize(12)
              Text(`${this.favoriteCount}本收藏`)
                .fontSize(11)
                .fontColor('#666666')
                .margin({ left: 4 })
            }
          }
          
          if (this.recentCount > 0) {
            Row() {
              Text('📖')
                .fontSize(12)
              Text(`${this.recentCount}本在读`)
                .fontSize(11)
                .fontColor('#666666')
                .margin({ left: 4 })
            }
            .margin({ left: this.favoriteCount > 0 ? 16 : 0 })
          }
        }
        .width('100%')
        .margin({ top: 12 })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .onClick(() => {
      router.pushUrl({ url: 'pages/NovelBookshelfPage' });
    })
  }
}

/**
 * 小说快捷入口按钮
 */
@Component
export struct NovelQuickButton {
  build() {
    Column() {
      Text('📚')
        .fontSize(24)
      Text('小说')
        .fontSize(11)
        .fontColor('#666666')
        .margin({ top: 4 })
    }
    .width(60)
    .height(70)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      router.pushUrl({ url: 'pages/NovelBookshelfPage' });
    })
  }
}

/**
 * 小说搜索快捷入口
 */
@Component
export struct NovelSearchButton {
  build() {
    Row() {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(20)
        .fontColor(['#999999'])
      
      Text('搜索小说...')
        .fontSize(14)
        .fontColor('#999999')
        .margin({ left: 8 })
    }
    .width('100%')
    .height(40)
    .padding({ left: 16, right: 16 })
    .backgroundColor('#F5F5F5')
    .borderRadius(20)
    .onClick(() => {
      router.pushUrl({ url: 'pages/NovelSearchPage' });
    })
  }
}
