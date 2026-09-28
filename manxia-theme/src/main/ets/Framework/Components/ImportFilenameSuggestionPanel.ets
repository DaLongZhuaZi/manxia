import { ThemeAwareState, ThemeAwareHelper } from './ThemeAware';
import {
  ImportFilenameParseResult,
  ImportFilenameMetadataCandidate
} from 'manxia_core/src/main/ets/Framework/Services/ImportFilenameIntelligenceService';

@Component
export struct ImportFilenameSuggestionPanel {
  @Prop themeState: ThemeAwareState;
  @Prop parseResult: ImportFilenameParseResult | null = null;
  @Prop currentTitle: string = '';
  @Prop currentAuthor: string = '';
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  onApplyCandidate: (candidate: ImportFilenameMetadataCandidate) => void = () => {};
  onApplyTitle: (title: string) => void = () => {};
  onApplyAuthor: (author: string) => void = () => {};

  private hasSuggestions(): boolean {
    if (!this.parseResult) {
      return false;
    }
    return this.parseResult.titleOptions.length > 0 ||
      this.parseResult.authorOptions.length > 0 ||
      this.parseResult.candidates.length > 0;
  }

  build() {
    Column() {
      if (this.hasSuggestions() && this.parseResult) {
        Column({ space: 10 }) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.lightbulb'))
              .fontSize(15)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])

            Text('文件名智能建议')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          }
          .width('100%')

          Text(`来源文件：${this.parseResult.fileName}`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          this.buildOptionRow('标题候选', this.parseResult.titleOptions.slice(0, 6), this.currentTitle, (value: string) => {
            this.onApplyTitle(value);
          })

          if (this.parseResult.authorOptions.length > 0) {
            this.buildOptionRow('作者候选', this.parseResult.authorOptions.slice(0, 6), this.currentAuthor, (value: string) => {
              this.onApplyAuthor(value);
            })
          }

          Column({ space: 8 }) {
            ForEach(this.parseResult.candidates.slice(0, 3), (candidate: ImportFilenameMetadataCandidate) => {
              this.buildCandidateCard(candidate)
            }, (candidate: ImportFilenameMetadataCandidate): string => candidate.key)
          }
          .width('100%')
        }
        .width('100%')
        .padding(12)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme) + 'B8')
        .borderRadius(10)
      }
    }
    .width('100%')
  }

  @Builder
  private buildOptionRow(
    label: string,
    options: string[],
    currentValue: string,
    onApply: (value: string) => void
  ) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')

      Scroll() {
        Row({ space: 8 }) {
          ForEach(options, (value: string) => {
            Text(value)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(this.normalizeValue(value) === this.normalizeValue(currentValue)
                ? ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .backgroundColor(this.normalizeValue(value) === this.normalizeValue(currentValue)
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
              .borderRadius(14)
              .onClick(() => {
                onApply(value);
              })
          }, (value: string): string => `${label}_${value}`)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private buildCandidateCard(candidate: ImportFilenameMetadataCandidate) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(candidate.title || '未识别标题')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          if (candidate.author.length > 0) {
            Text(`作者：${candidate.author}`)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .layoutWeight(1)

        Button('套用')
          .fontSize(11)
          .height(28)
          .padding({ left: 10, right: 10 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
          .borderRadius(14)
          .fontFamily(this.appFontFamily)
          .onClick(() => {
            this.onApplyCandidate(candidate);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        this.buildMetaChip(candidate.reason)
        this.buildMetaChip(`置信 ${(candidate.confidence * 100).toFixed(0)}%`)
        if (candidate.language.length > 0) {
          this.buildMetaChip(this.formatLanguageLabel(candidate.language))
        }
        if (candidate.publisher.length > 0) {
          this.buildMetaChip(candidate.publisher)
        }
        if (candidate.chapterNumber !== undefined) {
          this.buildMetaChip(`章节 ${candidate.chapterNumber}`)
        }
        if (candidate.volumeNumber !== undefined) {
          this.buildMetaChip(`卷 ${candidate.volumeNumber}`)
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(10)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(8)
  }

  @Builder
  private buildMetaChip(text: string) {
    Text(text)
      .fontSize(10)
      .fontFamily(this.appFontFamily)
      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(10)
      .margin({ right: 6, bottom: 6 })
  }

  private formatLanguageLabel(language: string): string {
    switch (language) {
      case 'zh-CN':
        return '简体中文';
      case 'zh-TW':
        return '繁體中文';
      case 'en':
        return 'English';
      case 'ja':
        return '日本語';
      case 'ko':
        return '한국어';
      default:
        return language;
    }
  }

  private normalizeValue(value: string): string {
    return value.trim().toLowerCase().replace(/[\s_\-|｜【】\[\]\(\)（）{}「」『』《》<>〈〉'"`.:：]+/g, '');
  }
}
