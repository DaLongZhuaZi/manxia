import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
// 文件路径: entry/src/main/ets/Framework/Components/ShareLinkDialogComponent.ets
// 职责: 分享直达链接对话框组件，样式与 DownloadDialogComponent 完全一致

import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { SourceDialogScaffold } from './SourceDialogScaffold';
import { UnifiedContent, UnifiedContentType } from '../../Models/UnifiedContentModels';

const TAG = 'ShareLinkDialogComponent';
const WEB_DOMAIN: string = 'manxia.top';

interface ShareOnlineEBookExtendedData {
  sourceId?: string;
  sourceName?: string;
  sourcePkg?: string;
  onlineReaderUrl?: string;
}

@Component
export struct ShareLinkDialogComponent {
  @Prop content: UnifiedContent | null = null;
  @Prop displaySourceName: string = '';
  @Prop themeState: ThemeAwareState = new ThemeAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @Prop @Watch('onLoadSignalChanged') loadSignal: number = 0;

  @State showShareDialog: boolean = false;
  @State shareLinkText: string = '';
  @State selectedLinkType: 'app' | 'web' = 'app';

  // 缓存两种链接
  private appLink: string = '';
  private webLink: string = '';

  onLoadSignalChanged(): void {
    if (this.loadSignal > 0) {
      this.showShareOptions();
    }
  }

  // ── 对话框控制 ──

  showShareOptions(): void {
    if (!this.content) {
      return;
    }

    this.appLink = this.buildDeepLink();
    this.webLink = this.buildWebLink();

    if (!this.appLink && !this.webLink) {
      this.getUIContext().getPromptAction().showToast({ message: '无法生成分享链接', duration: 1500 });
      return;
    }

    // 默认选择可用的链接类型
    this.selectedLinkType = this.appLink ? 'app' : 'web';
    this.shareLinkText = this.selectedLinkType === 'app' ? this.appLink : this.webLink;

    this.getUIContext().animateTo({
      duration: 220,
      curve: Curve.EaseOut
    }, () => {
      this.showShareDialog = true;
    });
  }

  closeShareDialog(): void {
    this.getUIContext().animateTo({
      duration: 180,
      curve: Curve.EaseIn
    }, () => {
      this.showShareDialog = false;
    });
  }

  private switchLinkType(type: 'app' | 'web'): void {
    this.selectedLinkType = type;
    this.shareLinkText = type === 'app' ? this.appLink : this.webLink;
  }

  // ── 链接生成 ──

  private buildDeepLink(): string {
    if (!this.content) {
      return '';
    }

    const contentType: UnifiedContentType = this.content.contentType;
    const sourceName: string = this.getContentSourceTokenForLink();
    const contentId: string = this.content.id;

    if (contentType === UnifiedContentType.MANGA) {
      if (!sourceName || !contentId) {
        return '';
      }
      return `manxia://detail/${encodeURIComponent(sourceName)}/${encodeURIComponent(contentId)}`;
    }

    if (contentType === UnifiedContentType.NOVEL) {
      if (!contentId) {
        return '';
      }
      const novelSourceId: string = this.content.sourceId || sourceName;
      return `manxia://novel/detail?s=${encodeURIComponent(novelSourceId)}&b=${encodeURIComponent(contentId)}`;
    }

    if (contentType === UnifiedContentType.EBOOK && this.isOnlineEBookForShare()) {
      if (!sourceName || !contentId) {
        return '';
      }
      return `manxia://detail/${encodeURIComponent(sourceName)}/${encodeURIComponent(contentId)}`;
    }

    return '';
  }

  private buildWebLink(): string {
    if (!this.content) {
      return '';
    }

    const contentType: UnifiedContentType = this.content.contentType;
    const sourceName: string = this.getContentSourceTokenForLink();
    const contentId: string = this.content.id;

    if (contentType === UnifiedContentType.MANGA) {
      if (!sourceName || !contentId) {
        return '';
      }
      return `https://${WEB_DOMAIN}/d/${encodeURIComponent(sourceName)}/${encodeURIComponent(contentId)}`;
    }

    if (contentType === UnifiedContentType.NOVEL) {
      if (!contentId) {
        return '';
      }
      const novelSourceId: string = this.content.sourceId || sourceName;
      return `https://${WEB_DOMAIN}/n?s=${encodeURIComponent(novelSourceId)}&b=${encodeURIComponent(contentId)}`;
    }

    if (contentType === UnifiedContentType.EBOOK && this.isOnlineEBookForShare()) {
      if (!sourceName || !contentId) {
        return '';
      }
      return `https://${WEB_DOMAIN}/d/${encodeURIComponent(sourceName)}/${encodeURIComponent(contentId)}`;
    }

    return '';
  }

  private getContentSourceTokenForLink(): string {
    if (!this.content) {
      return '';
    }
    const directSource: string = this.normalizeLinkText(this.content.sourcePkg) ||
      this.normalizeLinkText(this.content.sourceName) ||
      this.normalizeLinkText(this.content.sourceId);
    if (directSource.length > 0) {
      return directSource;
    }
    if (this.content.contentType !== UnifiedContentType.EBOOK) {
      return '';
    }
    const extendedData: ShareOnlineEBookExtendedData | null = this.getOnlineEBookExtendedData();
    if (!extendedData) {
      return '';
    }
    return this.normalizeLinkText(extendedData.sourcePkg) ||
      this.normalizeLinkText(extendedData.sourceName) ||
      this.normalizeLinkText(extendedData.sourceId);
  }

  private isOnlineEBookForShare(): boolean {
    if (!this.content || this.content.contentType !== UnifiedContentType.EBOOK) {
      return false;
    }
    if (!this.content.isLocal) {
      return true;
    }
    if (this.isHttpUrl(this.content.id)) {
      return true;
    }
    const extendedData: ShareOnlineEBookExtendedData | null = this.getOnlineEBookExtendedData();
    if (!extendedData) {
      return false;
    }
    return this.normalizeLinkText(extendedData.sourceId).length > 0 ||
      this.normalizeLinkText(extendedData.sourceName).length > 0 ||
      this.normalizeLinkText(extendedData.sourcePkg).length > 0 ||
      this.normalizeLinkText(extendedData.onlineReaderUrl).length > 0;
  }

  private getOnlineEBookExtendedData(): ShareOnlineEBookExtendedData | null {
    if (!this.content) {
      return null;
    }
    const filePath: string = this.normalizeLinkText(this.content.filePath);
    if (filePath.length <= 0 || !filePath.startsWith('{')) {
      return null;
    }
    try {
      return SafeUtils.parseObj(filePath) as ShareOnlineEBookExtendedData;
    } catch (error) {
      logger.debug(TAG, `解析在线电子书分享扩展数据失败: ${String(error)}`);
      return null;
    }
  }

  private isHttpUrl(value: string | undefined | null): boolean {
    const text: string = this.normalizeLinkText(value);
    return text.startsWith('http://') || text.startsWith('https://');
  }

  private normalizeLinkText(value: string | undefined | null): string {
    if (value === undefined || value === null) {
      return '';
    }
    return String(value).trim();
  }

  private isLikelySourceIdentifier(value: string): boolean {
    const normalized: string = this.normalizeLinkText(value).toLowerCase();
    if (normalized.length <= 0) {
      return false;
    }
    if (normalized.startsWith('http://') || normalized.startsWith('https://') || normalized.indexOf('://') >= 0) {
      return true;
    }
    if (normalized.startsWith('id_')) {
      return true;
    }
    if (normalized.startsWith('com.') && normalized.indexOf('.extension.') >= 0) {
      return true;
    }
    return /^[a-z0-9_-]+(\.[a-z0-9_-]+){2,}$/i.test(normalized);
  }

  private getDisplaySourceName(): string {
    const explicitDisplayName: string = this.normalizeLinkText(this.displaySourceName);
    if (explicitDisplayName.length > 0) {
      return explicitDisplayName;
    }
    const contentSourceName: string = this.normalizeLinkText(this.content?.sourceName);
    if (contentSourceName.length > 0 && !this.isLikelySourceIdentifier(contentSourceName)) {
      return contentSourceName;
    }
    const extendedData: ShareOnlineEBookExtendedData | null = this.getOnlineEBookExtendedData();
    if (!extendedData) {
      return '';
    }
    const extendedSourceName: string = this.normalizeLinkText(extendedData.sourceName);
    return this.isLikelySourceIdentifier(extendedSourceName) ? '' : extendedSourceName;
  }

  private getSourceLabel(): string {
    if (!this.content) {
      return '来源';
    }
    return this.content.contentType === UnifiedContentType.NOVEL ? '书源' : '图源';
  }

  private shouldShowDisplaySourceName(): boolean {
    if (!this.content) {
      return false;
    }
    if (this.getDisplaySourceName().length <= 0) {
      return false;
    }
    if (this.content.contentType === UnifiedContentType.NOVEL) {
      return true;
    }
    if (this.content.contentType === UnifiedContentType.MANGA) {
      return !this.content.isLocal;
    }
    if (this.content.contentType === UnifiedContentType.EBOOK) {
      return this.isOnlineEBookForShare();
    }
    return false;
  }

  // ── 操作 ──

  private copyLinkToClipboard(): void {
    if (!this.shareLinkText) {
      return;
    }
    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.shareLinkText);
    const systemPasteboard = pasteboard.getSystemPasteboard();
    systemPasteboard.setData(pasteData);
    this.getUIContext().getPromptAction().showToast({ message: '链接已复制', duration: 1500 });
    this.closeShareDialog();
  }

  private async executeShareLink(): Promise<void> {
    if (!this.shareLinkText) {
      return;
    }
    try {
      const uiContext = this.getUIContext();
      const hostContext = uiContext ? uiContext.getHostContext() : null;
      if (!hostContext) {
        throw new Error('hostContext is null');
      }
      const abilityContext = hostContext as common.UIAbilityContext;
      const title: string = this.content?.title || '分享内容';
      const description: string = `${this.content?.title || ''} - ${this.content?.author || ''}`;
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.PLAIN_TEXT,
        content: this.shareLinkText,
        title: title,
        description: description
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      await controller.show(abilityContext, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE
      });
      this.closeShareDialog();
    } catch (error) {
      const errMsg: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `分享失败: ${errMsg}`);
      this.getUIContext().getPromptAction().showToast({ message: '分享失败', duration: 1500 });
    }
  }

  private getContentTypeLabel(): string {
    if (!this.content) return '内容';
    switch (this.content.contentType) {
      case UnifiedContentType.MANGA:
        return '漫画';
      case UnifiedContentType.NOVEL:
        return '小说';
      case UnifiedContentType.EBOOK:
        return '电子书';
      default:
        return '内容';
    }
  }

  // ── 主对话框 ──

  @Builder
  buildShareLinkDialog() {
    if (this.showShareDialog && this.content) {
      SourceDialogScaffold({
        themeState: this.themeState,
        onMaskTap: () => this.closeShareDialog(),
        dialogWidth: '90%',
        maxWidth: 400,
        contentPadding: 24,
        useMaskBlur: true
      }) {
        Column({ space: 20 }) {
            // 标题栏
            Row() {
              Text('分享链接')
                .fontSize(20)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

              Blank()

              Button() {
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(18)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary',
                    this.themeState.currentTheme)])
              }
              .width(32)
              .height(32)
              .backgroundColor(Color.Transparent)
              .onClick(() => this.closeShareDialog())
            }
            .width('100%')

            // 内容信息
            Column({ space: 8 }) {
              Row({ space: 8 }) {
                Text(this.getContentTypeLabel())
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                  .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) + '15')
                  .borderRadius(4)

                Text(this.content.title || '未知内容')
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')

              if (this.content.author) {
                Text(this.content.author)
                  .fontSize(13)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }

              if (this.shouldShowDisplaySourceName()) {
                Row({ space: 6 }) {
                  Text(`${this.getSourceLabel()}：`)
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

                  Text(this.getDisplaySourceName())
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                }
                .width('100%')
              }
            }
            .width('100%')

            // 链接类型选择
            Row({ space: 8 }) {
              Button() {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.link'))
                    .fontSize(14)
                    .fontColor([this.selectedLinkType === 'app'
                      ? Color.White
                      : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
                  Text('APP 内链')
                    .fontSize(13)
                    .fontFamily(this.appFontFamily)
                    .fontColor(this.selectedLinkType === 'app'
                      ? Color.White
                      : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                }
              }
              .height(36)
              .padding({ left: 14, right: 14 })
              .backgroundColor(this.selectedLinkType === 'app'
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .borderRadius(18)
              .enabled(!!this.appLink)
              .opacity(this.appLink ? 1.0 : 0.4)
              .onClick(() => this.switchLinkType('app'))

              Button() {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.globe_badge_message'))
                    .fontSize(14)
                    .fontColor([this.selectedLinkType === 'web'
                      ? Color.White
                      : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
                  Text('网页链接')
                    .fontSize(13)
                    .fontFamily(this.appFontFamily)
                    .fontColor(this.selectedLinkType === 'web'
                      ? Color.White
                      : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                }
              }
              .height(36)
              .padding({ left: 14, right: 14 })
              .backgroundColor(this.selectedLinkType === 'web'
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .borderRadius(18)
              .enabled(!!this.webLink)
              .opacity(this.webLink ? 1.0 : 0.4)
              .onClick(() => this.switchLinkType('web'))
            }
            .width('100%')

            // 链接显示
            Column({ space: 4 }) {
              Text(this.selectedLinkType === 'app' ? 'APP 内链（需安装漫匣）' : '网页链接（任意浏览器可打开）')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .width('100%')

              Text(this.shareLinkText)
                .fontSize(12)
                .fontFamily('monospace')
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .width('100%')
                .padding(12)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                .borderRadius(8)
            }
            .width('100%')

            // 底部按钮
            Row({ space: 12 }) {
              Button() {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.link'))
                    .fontSize(16)
                    .fontColor([Color.White])
                  Text('复制链接')
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(Color.White)
                }
              }
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .height(44)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .layoutWeight(1)
              .borderRadius(22)
              .onClick(() => this.copyLinkToClipboard())

              Button() {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.share'))
                    .fontSize(16)
                    .fontColor([Color.White])
                  Text('分享')
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(Color.White)
                }
              }
              .height(44)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .layoutWeight(1)
              .borderRadius(22)
              .onClick(() => {
                void this.executeShareLink();
              })
            }
            .width('100%')
          }
          .width('100%')
      }
    }
  }

  build() {
    if (this.showShareDialog && this.content) {
      this.buildShareLinkDialog()
    } else {
      Column()
        .width(0)
        .height(0)
    }
  }
}
