import { ThemeAwareHelper, ThemeAwareState } from '../Framework/Components/ThemeAware';
import { SubscriptionExecutionStatus } from '../Framework/Subscription';

export enum ContentTrackingHighlightTone {
  PRIMARY = 'primary',
  SUCCESS = 'success',
  WARNING = 'warning',
  INFO = 'info',
  NEUTRAL = 'neutral'
}

export interface ContentTrackingHighlight {
  id: string;
  text: string;
  tone: ContentTrackingHighlightTone;
}

export interface ContentTrackingCardState {
  isLoading: boolean;
  isBusy: boolean;
  supported: boolean;
  unsupportedReason: string;
  hasRule: boolean;
  enabled: boolean;
  ruleName: string;
  providerText: string;
  conditionSummary: string;
  actionSummary: string;
  statusText: string;
  lastCheckText: string;
  chapterSummary: string;
  latestItemTitle: string;
  lastStatus: SubscriptionExecutionStatus;
  conditionHighlights: ContentTrackingHighlight[];
  actionHighlights: ContentTrackingHighlight[];
}

const EMPTY_CONTENT_TRACKING_HIGHLIGHTS: ContentTrackingHighlight[] = [];

export interface ContentTrackingCardCallbacks {
  onConfigure: () => void;
  onRunNow: () => void;
  onToggleEnabled: () => void;
  onOpenManagement: () => void;
}

const DEFAULT_CONTENT_TRACKING_CARD_STATE: ContentTrackingCardState = {
  isLoading: false,
  isBusy: false,
  supported: false,
  unsupportedReason: '',
  hasRule: false,
  enabled: false,
  ruleName: '',
  providerText: '',
  conditionSummary: '',
  actionSummary: '',
  statusText: '',
  lastCheckText: '',
  chapterSummary: '',
  latestItemTitle: '',
  lastStatus: SubscriptionExecutionStatus.NO_UPDATE,
  conditionHighlights: EMPTY_CONTENT_TRACKING_HIGHLIGHTS,
  actionHighlights: EMPTY_CONTENT_TRACKING_HIGHLIGHTS
};

const DEFAULT_CONTENT_TRACKING_CARD_CALLBACKS: ContentTrackingCardCallbacks = {
  onConfigure: () => {},
  onRunNow: () => {},
  onToggleEnabled: () => {},
  onOpenManagement: () => {}
};

@Component
export struct ContentTrackingStatusCard {
  @Prop state: ContentTrackingCardState = DEFAULT_CONTENT_TRACKING_CARD_STATE;
  @Prop themeState: ThemeAwareState = new ThemeAwareState();
  @Prop appFontFamily: string = 'HarmonyOS Sans';
  @Prop callbacks: ContentTrackingCardCallbacks = DEFAULT_CONTENT_TRACKING_CARD_CALLBACKS;
  @State private isExpanded: boolean = false;

  private getStatusPillText(): string {
    if (this.state.isLoading) {
      return '读取中';
    }
    if (!this.state.supported) {
      return '暂不支持';
    }
    if (!this.state.hasRule) {
      return '未开启';
    }
    return this.state.enabled ? '已开启' : '已暂停';
  }

  private getStatusPillColor(): ResourceColor {
    if (this.state.isLoading) {
      return ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme);
    }
    if (!this.state.supported) {
      return ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme);
    }
    if (!this.state.hasRule) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme);
    }
    if (!this.state.enabled) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme);
    }
    return ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme);
  }

  private getExecutionColor(): ResourceColor {
    if (this.state.lastStatus === SubscriptionExecutionStatus.SUCCESS) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme);
    }
    if (this.state.lastStatus === SubscriptionExecutionStatus.NO_UPDATE) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme);
    }
    if (this.state.lastStatus === SubscriptionExecutionStatus.SKIPPED) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme);
    }
    if (this.state.lastStatus === SubscriptionExecutionStatus.FAILED) {
      return ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme);
    }
    if (this.state.lastStatus === SubscriptionExecutionStatus.UNSUPPORTED) {
      return ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme);
    }
    return ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme);
  }

  private getHeadlineText(): string {
    if (this.state.isLoading) {
      return '正在读取提醒状态';
    }
    if (!this.state.supported) {
      return this.state.unsupportedReason.length > 0
        ? this.state.unsupportedReason
        : '这类内容暂时还不能自动检查';
    }
    if (!this.state.hasRule) {
      return '这本内容还没开始提醒';
    }
    if (this.state.statusText.length > 0) {
      return this.state.statusText;
    }
    return this.state.enabled ? '更新提醒已开启' : '更新提醒已暂停';
  }

  private getChapterSummaryText(): string {
    if (this.state.chapterSummary.length > 0) {
      return this.state.chapterSummary;
    }
    if (!this.state.supported) {
      return '暂不支持';
    }
    if (!this.state.hasRule) {
      return '还没有提醒';
    }
    if (!this.state.enabled) {
      return '已暂停自动检查';
    }
    if (this.state.latestItemTitle.length > 0) {
      return this.state.latestItemTitle;
    }
    return '还没检查过';
  }

  private toggleExpanded(): void {
    this.isExpanded = !this.isExpanded;
  }

  private getChapterSummaryAccentColor(): ResourceColor {
    if (!this.state.supported || !this.state.hasRule) {
      return this.getStatusPillColor();
    }
    return this.getExecutionColor();
  }

  private getActionButtonForegroundColor(isPrimary: boolean): ResourceColor {
    return isPrimary
      ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)
      : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme);
  }

  private getActionButtonBackgroundColor(isPrimary: boolean): ResourceColor {
    return isPrimary
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
      : ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme);
  }

  private getHighlightColor(tone: ContentTrackingHighlightTone): ResourceColor {
    if (tone === ContentTrackingHighlightTone.SUCCESS) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme);
    }
    if (tone === ContentTrackingHighlightTone.WARNING) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme);
    }
    if (tone === ContentTrackingHighlightTone.INFO) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme);
    }
    if (tone === ContentTrackingHighlightTone.NEUTRAL) {
      return ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme);
    }
    return ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme);
  }

  @Builder
  private buildSummaryRow(titleText: string, valueText: string, accentColor: ResourceColor) {
    Row({ space: 12 }) {
      Column({ space: 5 }) {
        Text(titleText)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(valueText)
          .fontSize(13)
          .lineHeight(19)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row() {
        Blank()
      }
      .width(28)
      .height(4)
      .backgroundColor(accentColor + '88')
      .borderRadius(2)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(14)
  }

  @Builder
  private buildActionButton(
    label: string,
    symbol: Resource,
    isPrimary: boolean,
    enabled: boolean,
    onClick: () => void
  ) {
    Button() {
      Row({ space: 8 }) {
        SymbolGlyph(symbol)
          .fontSize(15)
          .fontColor([this.getActionButtonForegroundColor(isPrimary)])
        Text(label)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getActionButtonForegroundColor(isPrimary))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
    }
    .width('100%')
    .height(40)
    .padding({ left: 12, right: 12 })
    .backgroundColor(this.getActionButtonBackgroundColor(isPrimary))
    .borderRadius(20)
    .enabled(enabled)
    .opacity(enabled ? 1 : 0.55)
    .onClick(() => onClick())
  }

  @Builder
  private buildHighlightChip(item: ContentTrackingHighlight) {
    Row({ space: 10 }) {
      Row() {
        Blank()
      }
      .width(6)
      .height(6)
      .borderRadius(3)
      .backgroundColor(this.getHighlightColor(item.tone))

      Text(item.text)
        .fontSize(12)
        .lineHeight(18)
        .fontFamily(this.appFontFamily)
        .fontColor(this.getHighlightColor(item.tone))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(this.getHighlightColor(item.tone) + '12')
    .borderRadius(12)
  }

  @Builder
  private buildHighlightSection(titleText: string, items: ContentTrackingHighlight[]) {
    Column({ space: 8 }) {
      Text(titleText)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')
      Column({ space: 8 }) {
        ForEach(items, (item: ContentTrackingHighlight) => {
          this.buildHighlightChip(item)
        }, (item: ContentTrackingHighlight): string => item.id)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private buildExpandedDetailItem(titleText: string, valueText: string, accentColor: ResourceColor) {
    Column({ space: 6 }) {
      Text(titleText)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(valueText)
        .fontSize(13)
        .lineHeight(20)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Row() {
        Blank()
      }
      .width(36)
      .height(4)
      .borderRadius(2)
      .backgroundColor(accentColor + '88')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(14)
  }

  @Builder
  private buildActionSection() {
    Column({ space: 10 }) {
      Text('快捷操作')
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')

      if (this.state.supported) {
        Row({ space: 10 }) {
          Column() {
            this.buildActionButton(
              this.state.hasRule ? '调整提醒' : '开启提醒',
              $r('sys.symbol.gearshape'),
              true,
              !this.state.isBusy,
              this.callbacks.onConfigure
            )
          }
          .layoutWeight(1)

          if (this.state.hasRule) {
            Column() {
              this.buildActionButton(
                this.state.isBusy ? '检查中...' : '现在检查',
                $r('sys.symbol.bookshelf_badge_checkmark'),
                false,
                !this.state.isBusy,
                this.callbacks.onRunNow
              )
            }
            .layoutWeight(1)
          } else {
            Column() {
              this.buildActionButton(
                '打开提醒页',
                $r('sys.symbol.bookshelf_badge_checkmark'),
                false,
                !this.state.isBusy,
                this.callbacks.onOpenManagement
              )
            }
            .layoutWeight(1)
          }
        }
        .width('100%')
      }

      if (this.state.hasRule) {
        Row({ space: 10 }) {
          Column() {
            this.buildActionButton(
              this.state.enabled ? '暂停提醒' : '恢复提醒',
              this.state.enabled ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'),
              false,
              !this.state.isBusy,
              this.callbacks.onToggleEnabled
            )
          }
          .layoutWeight(1)

          Column() {
            this.buildActionButton(
              '打开提醒页',
              $r('sys.symbol.bookshelf_badge_checkmark'),
              false,
              !this.state.isBusy,
              this.callbacks.onOpenManagement
            )
          }
          .layoutWeight(1)
        }
        .width('100%')
      }

      if (!this.state.supported) {
        this.buildActionButton(
          '打开提醒页',
          $r('sys.symbol.bookshelf_badge_checkmark'),
          false,
          !this.state.isBusy,
          this.callbacks.onOpenManagement
        )
      }
    }
    .width('100%')
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.bookshelf_badge_checkmark'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          Text('更新提醒')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }

        Blank()

        Text(this.getStatusPillText())
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getStatusPillColor())
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(this.getStatusPillColor() + '18')
          .borderRadius(12)
      }
      .width('100%')

      Column({ space: 10 }) {
        this.buildSummaryRow('当前状态', this.getHeadlineText(), this.getStatusPillColor())
        this.buildSummaryRow(
          '上次检查',
          this.state.lastCheckText.length > 0 ? this.state.lastCheckText : '还没检查过',
          ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
        )
        this.buildSummaryRow(
          '更新情况',
          this.getChapterSummaryText(),
          this.getChapterSummaryAccentColor()
        )
        Text('自动检查目前只会在 APP 回到前台时补查，后台不会定时执行。')
          .fontSize(11)
          .lineHeight(17)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')

        Button() {
          Row({ space: 8 }) {
            Text(this.isExpanded ? '收起更多设置' : '展开更多设置')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Blank()
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(14)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
              .rotate({ angle: this.isExpanded ? 0 : -90 })
              .animation({ duration: 220, curve: Curve.EaseInOut })
          }
          .width('100%')
        }
        .width('100%')
        .height(38)
        .padding({ left: 12, right: 12 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
        .borderRadius(19)
        .onClick(() => {
          this.toggleExpanded();
        })
      }
      .width('100%')
      .padding(14)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(16)

      if (this.isExpanded) {
        Column({ space: 12 }) {
          if (this.state.providerText.length > 0) {
            this.buildExpandedDetailItem(
              '内容来源',
              this.state.providerText,
              ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
            )
          }

          if (this.state.ruleName.length > 0) {
            this.buildExpandedDetailItem(
              '提醒名称',
              this.state.ruleName,
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            )
          }

          if (this.state.latestItemTitle.length > 0) {
            this.buildExpandedDetailItem(
              '最近更新',
              this.state.latestItemTitle,
              ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
            )
          }

          if (this.state.hasRule) {
            this.buildExpandedDetailItem(
              '怎么检查',
              this.state.conditionSummary.length > 0 ? this.state.conditionSummary : '按默认方式',
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            )
            this.buildExpandedDetailItem(
              '发现更新后',
              this.state.actionSummary.length > 0 ? this.state.actionSummary : '只检查，不自动处理',
              ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
            )
          }

          if (this.state.conditionHighlights.length > 0) {
            this.buildHighlightSection('检查细节', this.state.conditionHighlights)
          }

          if (this.state.actionHighlights.length > 0) {
            this.buildHighlightSection('处理方式', this.state.actionHighlights)
          }

          this.buildActionSection()
        }
        .width('100%')
        .transition(
          TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut })
            .combine(TransitionEffect.translate({ y: -10 }).animation({ duration: 220, curve: Curve.EaseOut }))
        )
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
