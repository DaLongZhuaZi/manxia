/**
 * 阅读目标卡片 - UI页面
 * 小卡片(2x2)：Apple Watch风格多圈圆环
 * 中卡片(2x4)：横向三个独立圆环
 * 大卡片(4x4)：上部圆环 + 下部最近阅读列表
 */

// 预览数据类型定义
class CardPreviewData {
  dimension: number = 4;
  mangaGoal: number = 60;
  mangaRead: number = 45;
  mangaProgress: number = 75;
  ebookGoal: number = 30;
  ebookRead: number = 20;
  ebookProgress: number = 67;
  novelGoal: number = 45;
  novelRead: number = 30;
  novelProgress: number = 67;
  hasMangaGoal: boolean = true;
  hasEbookGoal: boolean = true;
  hasNovelGoal: boolean = true;
  hasAnyGoal: boolean = true;
  recentCount: number = 6;
  recent1Id: string = 'preview_manga_1';
  recent1Title: string = '镖人';
  recent1Cover: string = '';
  recent1Progress: number = 45;
  recent1Type: string = 'manga';
  recent2Id: string = 'preview_ebook_1';
  recent2Title: string = '三体';
  recent2Cover: string = '';
  recent2Progress: number = 80;
  recent2Type: string = 'ebook';
  recent3Id: string = 'preview_novel_1';
  recent3Title: string = '斗破苍穹';
  recent3Cover: string = '';
  recent3Progress: number = 30;
  recent3Type: string = 'novel';
  recent4Id: string = 'preview_manga_2';
  recent4Title: string = '进击的巨人';
  recent4Cover: string = '';
  recent4Progress: number = 60;
  recent4Type: string = 'manga';
  recent5Id: string = 'preview_ebook_2';
  recent5Title: string = '流浪地球';
  recent5Cover: string = '';
  recent5Progress: number = 100;
  recent5Type: string = 'ebook';
  recent6Id: string = 'preview_novel_2';
  recent6Title: string = '凡人修仙传';
  recent6Cover: string = '';
  recent6Progress: number = 15;
  recent6Type: string = 'novel';
}

let cardStorage = new LocalStorage(new CardPreviewData());

@Entry(cardStorage)
@Component
struct ReadingProgressCard {
  // 卡片尺寸: 2=2x2, 3=2x4, 4=4x4 (FormDimension枚举值)
  @LocalStorageProp('dimension') dimension: number = 2;
  
  // 阅读目标数据
  @LocalStorageProp('mangaGoal') mangaGoal: number = 0;
  @LocalStorageProp('mangaRead') mangaRead: number = 0;
  @LocalStorageProp('mangaProgress') mangaProgress: number = 0;
  @LocalStorageProp('ebookGoal') ebookGoal: number = 0;
  @LocalStorageProp('ebookRead') ebookRead: number = 0;
  @LocalStorageProp('ebookProgress') ebookProgress: number = 0;
  @LocalStorageProp('novelGoal') novelGoal: number = 0;
  @LocalStorageProp('novelRead') novelRead: number = 0;
  @LocalStorageProp('novelProgress') novelProgress: number = 0;
  
  // 是否设置了目标
  @LocalStorageProp('hasMangaGoal') hasMangaGoal: boolean = false;
  @LocalStorageProp('hasEbookGoal') hasEbookGoal: boolean = false;
  @LocalStorageProp('hasNovelGoal') hasNovelGoal: boolean = false;
  @LocalStorageProp('hasAnyGoal') hasAnyGoal: boolean = false;
  
  // 最近阅读
  @LocalStorageProp('recentCount') recentCount: number = 0;
  @LocalStorageProp('recent1Id') recent1Id: string = '';
  @LocalStorageProp('recent1Title') recent1Title: string = '';
  @LocalStorageProp('recent1Cover') recent1Cover: string = '';
  @LocalStorageProp('recent1Progress') recent1Progress: number = 0;
  @LocalStorageProp('recent1Type') recent1Type: string = '';
  @LocalStorageProp('recent2Id') recent2Id: string = '';
  @LocalStorageProp('recent2Title') recent2Title: string = '';
  @LocalStorageProp('recent2Cover') recent2Cover: string = '';
  @LocalStorageProp('recent2Progress') recent2Progress: number = 0;
  @LocalStorageProp('recent2Type') recent2Type: string = '';
  @LocalStorageProp('recent3Id') recent3Id: string = '';
  @LocalStorageProp('recent3Title') recent3Title: string = '';
  @LocalStorageProp('recent3Cover') recent3Cover: string = '';
  @LocalStorageProp('recent3Progress') recent3Progress: number = 0;
  @LocalStorageProp('recent3Type') recent3Type: string = '';
  @LocalStorageProp('recent4Id') recent4Id: string = '';
  @LocalStorageProp('recent4Title') recent4Title: string = '';
  @LocalStorageProp('recent4Cover') recent4Cover: string = '';
  @LocalStorageProp('recent4Progress') recent4Progress: number = 0;
  @LocalStorageProp('recent4Type') recent4Type: string = '';
  @LocalStorageProp('recent5Id') recent5Id: string = '';
  @LocalStorageProp('recent5Title') recent5Title: string = '';
  @LocalStorageProp('recent5Cover') recent5Cover: string = '';
  @LocalStorageProp('recent5Progress') recent5Progress: number = 0;
  @LocalStorageProp('recent5Type') recent5Type: string = '';
  @LocalStorageProp('recent6Id') recent6Id: string = '';
  @LocalStorageProp('recent6Title') recent6Title: string = '';
  @LocalStorageProp('recent6Cover') recent6Cover: string = '';
  @LocalStorageProp('recent6Progress') recent6Progress: number = 0;
  @LocalStorageProp('recent6Type') recent6Type: string = '';

  // 颜色定义（三原色）
  private mangaColor: string = '#FF5A4D';      // 红色 - 漫画
  private ebookColor: string = '#27B579';      // 绿色 - 电子书
  private novelColor: string = '#4E7AF7';      // 蓝色 - 小说
  private bgColor: string = '#142033';         // 深色背景
  private ringTrackColor: string = '#32415C';
  private textColor: string = '#F5F7FF';
  private textSecondary: string = '#AAB6CF';

  build() {
    Column() {
      // FormDimension枚举: 2=2x2(小卡片), 3=2x4(中卡片), 4=4x4(大卡片)
      if (this.dimension === 2) {
        this.SmallCard()
      } else if (this.dimension === 3) {
        this.MediumCard()
      } else {
        this.LargeCard()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.bgColor)
    .borderRadius(16)
    .onClick(() => {
      if (this.dimension !== 4) {
        this.openAnalyticsFromWidget();
      }
    })
  }

  private openAnalyticsFromWidget(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: { targetPage: 'readingAnalytics' }
    });
  }

  private openRecentFromWidget(contentType: string, contentId: string): void {
    if (!contentType || !contentId) {
      this.openAnalyticsFromWidget();
      return;
    }
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: {
        targetPage: 'continueRead',
        contentType: contentType,
        contentId: contentId
      }
    });
  }

  private getTypeTag(type: string): string {
    if (type === 'manga') {
      return '漫';
    }
    if (type === 'ebook') {
      return '书';
    }
    return '说';
  }

  private getTypeColor(type: string): string {
    if (type === 'manga') {
      return this.mangaColor;
    }
    if (type === 'ebook') {
      return this.ebookColor;
    }
    return this.novelColor;
  }

  /**
   * 2x2 小卡片：Apple Watch风格多圈同心圆环
   */
  @Builder
  SmallCard() {
    Column() {
      if (!this.hasAnyGoal) {
        // 未设置目标时显示提示
        Column({ space: 4 }) {
          Text('阅')
            .fontSize(28)
            .fontColor(this.textColor)
            .fontWeight(FontWeight.Bold)
          Text('设置阅读目标')
            .fontSize(11)
            .fontColor(this.textSecondary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        // 多圈同心圆环
        Stack() {
          // 外圈 - 漫画（最大）
          if (this.hasMangaGoal) {
            Progress({
              value: this.mangaProgress,
              total: 100,
              type: ProgressType.Ring
            })
              .width(80)
              .height(80)
              .color(this.mangaColor)
              .backgroundColor(this.ringTrackColor)
              .style({ strokeWidth: 8 })
          }
          
          // 中圈 - 电子书
          if (this.hasEbookGoal) {
            Progress({
              value: this.ebookProgress,
              total: 100,
              type: ProgressType.Ring
            })
              .width(58)
              .height(58)
              .color(this.ebookColor)
              .backgroundColor(this.ringTrackColor)
              .style({ strokeWidth: 8 })
          }
          
          // 内圈 - 小说（最小）
          if (this.hasNovelGoal) {
            Progress({
              value: this.novelProgress,
              total: 100,
              type: ProgressType.Ring
            })
              .width(36)
              .height(36)
              .color(this.novelColor)
              .backgroundColor(this.ringTrackColor)
              .style({ strokeWidth: 6 })
          }
        }
        .width(80)
        .height(80)
        
        // 图例（带文字说明）
        Row({ space: 8 }) {
          if (this.hasMangaGoal) {
            this.LegendItem('漫', this.mangaColor)
          }
          if (this.hasEbookGoal) {
            this.LegendItem('书', this.ebookColor)
          }
          if (this.hasNovelGoal) {
            this.LegendItem('说', this.novelColor)
          }
        }
        .margin({ top: 4 })
      }
    }
    .width('100%')
    .height('100%')
    .padding(8)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 2x4 中卡片：横向显示三个独立圆环（纯圆环，不显示最近阅读）
   */
  @Builder
  MediumCard() {
    Column() {
      if (!this.hasAnyGoal) {
        Column({ space: 4 }) {
          Text('阅读目标')
            .fontSize(14)
            .fontColor(this.textColor)
            .fontWeight(FontWeight.Bold)
          Text('点击设置每日阅读目标')
            .fontSize(11)
            .fontColor(this.textSecondary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        // 三个圆环横向排列（夳满卡片）
        Row() {
          // 漫画
          if (this.hasMangaGoal) {
            this.MediumGoalRing('漫画', this.mangaProgress, this.mangaRead, this.mangaGoal, this.mangaColor)
          }
          
          // 电子书
          if (this.hasEbookGoal) {
            this.MediumGoalRing('电子书', this.ebookProgress, this.ebookRead, this.ebookGoal, this.ebookColor)
          }
          
          // 小说
          if (this.hasNovelGoal) {
            this.MediumGoalRing('小说', this.novelProgress, this.novelRead, this.novelGoal, this.novelColor)
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.SpaceEvenly)
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .padding(8)
  }

  /**
   * 中卡片专用圆环（更大尺寸）
   */
  @Builder
  MediumGoalRing(label: string, progress: number, readMinutes: number, goalMinutes: number, color: string) {
    Column({ space: 6 }) {
      Stack() {
        Progress({
          value: progress,
          total: 100,
          type: ProgressType.Ring
        })
          .width(60)
          .height(60)
          .color(color)
          .backgroundColor(this.ringTrackColor)
          .style({ strokeWidth: 7 })
        
        Text(`${progress}%`)
          .fontSize(12)
          .fontColor(this.textColor)
          .fontWeight(FontWeight.Bold)
      }
      .width(60)
      .height(60)
      
      Text(label)
        .fontSize(11)
        .fontColor(color)
        .fontWeight(FontWeight.Medium)
      
      Text(`${readMinutes}/${goalMinutes}分`)
        .fontSize(10)
        .fontColor(this.textSecondary)
    }
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 4x4 大卡片：上部圆环 + 下部最近阅读
   */
  @Builder
  LargeCard() {
    Column() {
      // 上半部分：阅读目标圆环
      Column() {
        Text('今日阅读目标')
          .fontSize(12)
          .fontColor(this.textSecondary)
          .width('100%')
        
        if (!this.hasAnyGoal) {
          Text('点击设置阅读目标')
            .fontSize(11)
            .fontColor(this.textSecondary)
            .margin({ top: 20 })
        } else {
          Row() {
            if (this.hasMangaGoal) {
              this.GoalRingItem('漫画', this.mangaProgress, this.mangaRead, this.mangaGoal, this.mangaColor)
            }
            if (this.hasEbookGoal) {
              this.GoalRingItem('电子书', this.ebookProgress, this.ebookRead, this.ebookGoal, this.ebookColor)
            }
            if (this.hasNovelGoal) {
              this.GoalRingItem('小说', this.novelProgress, this.novelRead, this.novelGoal, this.novelColor)
            }
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.SpaceEvenly)
          .alignItems(VerticalAlign.Center)
        }
      }
      .width('100%')
      .height('45%')
      .padding({ left: 12, right: 12, top: 12 })
      .onClick(() => {
        this.openAnalyticsFromWidget();
      })
      
      // 分割线
      Divider()
        .color(this.ringTrackColor)
        .width('90%')
      
      // 下半部分：最近阅读（多行列表显示）
      Column() {
        Text('最近阅读')
          .fontSize(12)
          .fontColor(this.textSecondary)
          .width('100%')
          .margin({ bottom: 6 })
        
        if (this.recentCount === 0) {
          Text('暂无阅读记录')
            .fontSize(11)
            .fontColor(this.textSecondary)
            .layoutWeight(1)
        } else {
          Column({ space: 3 }) {
            if (this.recent1Title !== '') {
              this.RecentListItem(this.recent1Title, this.recent1Type, this.recent1Cover, this.recent1Progress, this.recent1Id)
            }
            if (this.recent2Title !== '') {
              this.RecentListItem(this.recent2Title, this.recent2Type, this.recent2Cover, this.recent2Progress, this.recent2Id)
            }
            if (this.recent3Title !== '') {
              this.RecentListItem(this.recent3Title, this.recent3Type, this.recent3Cover, this.recent3Progress, this.recent3Id)
            }
            if (this.recent4Title !== '') {
              this.RecentListItem(this.recent4Title, this.recent4Type, this.recent4Cover, this.recent4Progress, this.recent4Id)
            }
            if (this.recent5Title !== '') {
              this.RecentListItem(this.recent5Title, this.recent5Type, this.recent5Cover, this.recent5Progress, this.recent5Id)
            }
            if (this.recent6Title !== '') {
              this.RecentListItem(this.recent6Title, this.recent6Type, this.recent6Cover, this.recent6Progress, this.recent6Id)
            }
          }
          .width('100%')
          .layoutWeight(1)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 12, right: 12, bottom: 8 })
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 单个目标圆环项
   */
  @Builder
  GoalRingItem(label: string, progress: number, readMinutes: number, goalMinutes: number, color: string) {
    Column({ space: 4 }) {
      Stack() {
        Progress({
          value: progress,
          total: 100,
          type: ProgressType.Ring
        })
          .width(50)
          .height(50)
          .color(color)
          .backgroundColor(this.ringTrackColor)
          .style({ strokeWidth: 6 })
        
        Text(`${progress}%`)
          .fontSize(10)
          .fontColor(this.textColor)
          .fontWeight(FontWeight.Bold)
      }
      .width(50)
      .height(50)
      
      Text(label)
        .fontSize(10)
        .fontColor(color)
      
      Text(`${readMinutes}/${goalMinutes}分钟`)
        .fontSize(9)
        .fontColor(this.textSecondary)
    }
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 图例圆点（仅圆点，无文字）
   */
  @Builder
  LegendDot(color: string) {
    Row()
      .width(8)
      .height(8)
      .borderRadius(4)
      .backgroundColor(color)
  }

  /**
   * 图例项（圆点+文字）
   */
  @Builder
  LegendItem(label: string, color: string) {
    Row({ space: 2 }) {
      Row()
        .width(6)
        .height(6)
        .borderRadius(3)
        .backgroundColor(color)
      Text(label)
        .fontSize(9)
        .fontColor(color)
    }
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 最近阅读列表项（多行显示，无封面）
   */
  @Builder
  RecentListItem(title: string, type: string, cover: string, progress: number, contentId: string) {
    Row({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        if (cover && cover.length > 0) {
          Image(cover)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        } else {
          Text(this.getTypeTag(type))
            .fontSize(10)
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Bold)
        }
      }
      .width(22)
      .height(22)
      .backgroundColor(this.getTypeColor(type))
      .borderRadius(4)
      .clip(true)

      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text(this.getTypeTag(type))
            .fontSize(9)
            .fontColor('#FFFFFF')
            .backgroundColor(this.getTypeColor(type))
            .borderRadius(2)
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })

          Text(title)
            .fontSize(10)
            .fontColor(this.textColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')

        Progress({
          value: Math.max(0, Math.min(progress, 100)),
          total: 100,
          type: ProgressType.Linear
        })
          .height(2)
          .borderRadius(1)
          .color(this.getTypeColor(type))
          .backgroundColor(this.ringTrackColor)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height(28)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 4, right: 4 })
    .borderRadius(6)
    .backgroundColor('#1C2B45')
    .onClick(() => {
      this.openRecentFromWidget(type, contentId);
    })
  }
}
