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
      return '未跟踪';
    }
    return this.state.enabled ? '已启用' : '已停用';
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
      return '正在读取当前内容的跟踪状态';
    }
    if (!this.state.supported) {
      return this.state.unsupportedReason.length > 0
        ? this.state.unsupportedReason
        : '当前内容暂不支持自动跟踪';
    }
    if (!this.state.hasRule) {
      return '当前内容尚未建立跟踪规则';
    }
    if (this.state.statusText.length > 0) {
      return this.state.statusText;
    }
    return this.state.enabled ? '当前规则已启用' : '当前规则已停用';
  }

  private getChapterSummaryText(): string {
    if (this.state.chapterSummary.length > 0) {
      return this.state.chapterSummary;
    }
    if (!this.state.supported) {
      return '当前内容暂不支持跟踪';
    }
    if (!this.state.hasRule) {
      return '尚未建立跟踪';
    }
    if (!this.state.enabled) {
      return '跟踪已暂停';
    }
    if (this.state.latestItemTitle.length > 0) {
      return this.state.latestItemTitle;
    }
    return '等待首次检查';
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
      Text('快速操作')
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')

      if (this.state.supported) {
        Row({ space: 10 }) {
          Column() {
            this.buildActionButton(
              this.state.hasRule ? '编辑跟踪' : '创建跟踪',
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
                this.state.isBusy ? '检查中...' : '立即检查',
                $r('sys.symbol.arrow_clockwise'),
                false,
                !this.state.isBusy,
                this.callbacks.onRunNow
              )
            }
            .layoutWeight(1)
          } else {
            Column() {
              this.buildActionButton(
                '管理页',
                $r('sys.symbol.rectangle_stack'),
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
              this.state.enabled ? '暂停跟踪' : '启用跟踪',
              this.state.enabled ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'),
              false,
              !this.state.isBusy,
              this.callbacks.onToggleEnabled
            )
          }
          .layoutWeight(1)

          Column() {
            this.buildActionButton(
              '管理页',
              $r('sys.symbol.rectangle_stack'),
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
          '管理页',
          $r('sys.symbol.rectangle_stack'),
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
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          Text('内容跟踪')
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
          this.state.lastCheckText.length > 0 ? this.state.lastCheckText : '尚未执行',
          ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
        )
        this.buildSummaryRow(
          '章节情况',
          this.getChapterSummaryText(),
          this.getChapterSummaryAccentColor()
        )

        Button() {
          Row({ space: 8 }) {
            Text(this.isExpanded ? '收起详细信息' : '展开详细信息')
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
              '跟踪来源',
              this.state.providerText,
              ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
            )
          }

          if (this.state.ruleName.length > 0) {
            this.buildExpandedDetailItem(
              '规则名称',
              this.state.ruleName,
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            )
          }

          if (this.state.latestItemTitle.length > 0) {
            this.buildExpandedDetailItem(
              '最近动态',
              this.state.latestItemTitle,
              ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
            )
          }

          if (this.state.hasRule) {
            this.buildExpandedDetailItem(
              '检查条件',
              this.state.conditionSummary.length > 0 ? this.state.conditionSummary : '未配置',
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            )
            this.buildExpandedDetailItem(
              '更新动作',
              this.state.actionSummary.length > 0 ? this.state.actionSummary : '仅检查更新',
              ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
            )
          }

          if (this.state.conditionHighlights.length > 0) {
            this.buildHighlightSection('条件细项', this.state.conditionHighlights)
          }

          if (this.state.actionHighlights.length > 0) {
            this.buildHighlightSection('执行细项', this.state.actionHighlights)
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
