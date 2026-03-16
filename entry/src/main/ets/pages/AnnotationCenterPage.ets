import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { logger } from '../Utils/Logger';
import { ThemeManager } from '../Framework/Managers/ThemeManager';
import { getUnifiedAnnotationManager, UnifiedAnnotationManager } from '../Framework/Annotations/UnifiedAnnotationManager';
import { UnifiedContentType } from '../Models/UnifiedContentModels';
import { UnifiedAnnotationRecord, UnifiedAnnotationType, HighlightLineType } from '../Models/AnnotationModels';

const TAG = 'AnnotationCenterPage';

type AnnotationFilterType = 'all' | 'bookmark' | 'highlight' | 'thought';

export interface AnnotationCenterPageParams {
  contentType: UnifiedContentType;
  contentId: string;
  contentTitle?: string;
}

  @Component
export struct AnnotationCenterPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  @State contentType: UnifiedContentType = UnifiedContentType.NOVEL;
  @State contentId: string = '';
  @State contentTitle: string = '摘录中心';
  @State filterType: AnnotationFilterType = 'all';
  @State records: UnifiedAnnotationRecord[] = [];
  @State visibleRecords: UnifiedAnnotationRecord[] = [];
  @State selectedRecordIds: string[] = [];
  @State isLoading: boolean = true;

  private annotationManager: UnifiedAnnotationManager = getUnifiedAnnotationManager();
  private themeManager = ThemeManager.getInstance();

  /**
   * 解析页面参数，优先使用 pathInfo，其次回退到 pathStack。
   */
  private parsePageParams(context: NavDestinationContext): AnnotationCenterPageParams | null {
    const pathInfo = context.pathInfo;
    const fromPathInfo = pathInfo ? pathInfo.param as AnnotationCenterPageParams : null;
    if (fromPathInfo && fromPathInfo.contentId) {
      logger.info(TAG, `参数解析成功(pathInfo): contentType=${fromPathInfo.contentType}, contentId=${fromPathInfo.contentId}`);
      return fromPathInfo;
    }

    const fromStack = context.pathStack.getParamByName('AnnotationCenterPage') as AnnotationCenterPageParams[];
    if (fromStack && fromStack.length > 0) {
      const latest = fromStack[fromStack.length - 1];
      if (latest && latest.contentId) {
        logger.info(TAG, `参数解析成功(pathStack): contentType=${latest.contentType}, contentId=${latest.contentId}`);
        return latest;
      }
    }
    logger.warn(TAG, '参数解析失败: 未找到有效的 AnnotationCenterPageParams');
    return null;
  }

  private getContentTypeLabel(type: UnifiedContentType): string {
    if (type === UnifiedContentType.MANGA) {
      return '漫画';
    }
    if (type === UnifiedContentType.EBOOK) {
      return '电子书';
    }
    return '小说';
  }

  private onFilterTypeChange(next: AnnotationFilterType): void {
    if (this.filterType === next) {
      return;
    }
    logger.info(TAG, `切换筛选类型: ${this.filterType} -> ${next}`);
    this.filterType = next;
    this.applyFilter();
  }

  /**
   * 根据当前筛选类型更新可见摘录列表，并同步已选状态。
   */
  private applyFilter(): void {
    if (this.filterType === 'all') {
      this.visibleRecords = [...this.records];
    } else {
      this.visibleRecords = this.records.filter((record: UnifiedAnnotationRecord) => {
        if (this.filterType === 'bookmark') {
          return record.annotationType === UnifiedAnnotationType.BOOKMARK;
        }
        if (this.filterType === 'highlight') {
          return record.annotationType === UnifiedAnnotationType.HIGHLIGHT;
        }
        return record.annotationType === UnifiedAnnotationType.THOUGHT;
      });
    }

    this.selectedRecordIds = this.selectedRecordIds.filter((id: string) =>
      this.visibleRecords.some((record: UnifiedAnnotationRecord) => record.id === id)
    );
    logger.debug(TAG, `筛选完成: type=${this.filterType}, visible=${this.visibleRecords.length}, selected=${this.selectedRecordIds.length}`);
  }

  /**
   * 加载当前内容的摘录数据。
   */
  private async loadAnnotations(): Promise<void> {
    if (!this.contentId) {
      logger.warn(TAG, '加载摘录跳过: contentId 为空');
      this.records = [];
      this.visibleRecords = [];
      this.selectedRecordIds = [];
      this.isLoading = false;
      return;
    }

    this.isLoading = true;
    logger.info(TAG, `开始加载摘录: contentType=${this.contentType}, contentId=${this.contentId}`);
    try {
      this.records = await this.annotationManager.getContentAnnotations(this.contentType, this.contentId);
      this.selectedRecordIds = [];
      this.applyFilter();
      logger.info(TAG, `摘录加载成功: total=${this.records.length}`);
    } catch (error) {
      logger.error(TAG, `加载摘录失败: ${String(error)}`);
      promptAction.showToast({ message: '加载摘录失败', duration: 1500 });
      this.records = [];
      this.visibleRecords = [];
      this.selectedRecordIds = [];
    } finally {
      this.isLoading = false;
    }
  }

  private isSelected(recordId: string): boolean {
    return this.selectedRecordIds.includes(recordId);
  }

  private toggleSelection(recordId: string): void {
    if (this.isSelected(recordId)) {
      this.selectedRecordIds = this.selectedRecordIds.filter((id: string) => id !== recordId);
    } else {
      this.selectedRecordIds = [...this.selectedRecordIds, recordId];
    }
    logger.debug(TAG, `切换选择状态: recordId=${recordId}, selected=${this.selectedRecordIds.length}`);
  }

  /**
   * 全选/取消全选当前筛选结果。
   */
  private toggleSelectAllVisible(): void {
    if (this.visibleRecords.length <= 0) {
      promptAction.showToast({ message: '当前筛选下无可选摘录', duration: 1500 });
      return;
    }
    const allSelected = this.visibleRecords.every((record: UnifiedAnnotationRecord) => this.isSelected(record.id));
    if (allSelected) {
      this.selectedRecordIds = [];
    } else {
      this.selectedRecordIds = this.visibleRecords.map((record: UnifiedAnnotationRecord) => record.id);
    }
    logger.info(TAG, `批量选择: allSelected=${!allSelected}, selected=${this.selectedRecordIds.length}`);
  }

  private getTypeLabel(type: UnifiedAnnotationType): string {
    if (type === UnifiedAnnotationType.BOOKMARK) {
      return '书签';
    }
    if (type === UnifiedAnnotationType.HIGHLIGHT) {
      return '划线';
    }
    return '想法';
  }

  private trimText(text: string, maxLength: number): string {
    if (text.length <= maxLength) {
      return text;
    }
    return `${text.substring(0, maxLength)}...`;
  }

  private getPrimaryText(record: UnifiedAnnotationRecord): string {
    if (record.annotationType === UnifiedAnnotationType.BOOKMARK) {
      if (record.title && record.title.trim().length > 0) {
        return record.title.trim();
      }
      if (record.quoteText && record.quoteText.trim().length > 0) {
        return this.trimText(record.quoteText.trim(), 120);
      }
      return '书签';
    }

    if (record.annotationType === UnifiedAnnotationType.HIGHLIGHT) {
      if (record.quoteText && record.quoteText.trim().length > 0) {
        return this.trimText(record.quoteText.trim(), 120);
      }
      return '划线';
    }

    if (record.textContent && record.textContent.trim().length > 0) {
      return this.trimText(record.textContent.trim(), 120);
    }
    if (record.quoteText && record.quoteText.trim().length > 0) {
      return this.trimText(record.quoteText.trim(), 120);
    }
    return '想法';
  }

  private getSecondaryText(record: UnifiedAnnotationRecord): string {
    if (record.annotationType === UnifiedAnnotationType.THOUGHT &&
      record.textContent.trim().length > 0 &&
      record.quoteText.trim().length > 0) {
      return `关联摘录：${this.trimText(record.quoteText.trim(), 80)}`;
    }
    if (record.annotationType === UnifiedAnnotationType.BOOKMARK &&
      record.title.trim().length > 0 &&
      record.quoteText.trim().length > 0) {
      return `摘录：${this.trimText(record.quoteText.trim(), 80)}`;
    }
    return '';
  }

  private getAnchorLabel(record: UnifiedAnnotationRecord): string {
    const parts: string[] = [];
    if (record.chapterTitle && record.chapterTitle.trim().length > 0) {
      parts.push(record.chapterTitle.trim());
    } else if (record.chapterIndex >= 0) {
      parts.push(`章节 ${record.chapterIndex + 1}`);
    }
    if (record.pageIndex >= 0) {
      parts.push(`P${record.pageIndex + 1}`);
    }
    if (record.pageProgress >= 0) {
      parts.push(`${Math.round(record.pageProgress * 100)}%`);
    }
    if (parts.length <= 0) {
      return '位置未记录';
    }
    return parts.join(' · ');
  }

  private getHighlightStyleLabel(record: UnifiedAnnotationRecord): string {
    if (!record.styleJson || record.styleJson.trim().length <= 0) {
      return '';
    }
    try {
      const styleObj = JSON.parse(record.styleJson) as Record<string, string>;
      const lineType = styleObj.lineType === HighlightLineType.WAVY ? '波浪线' : '下划线';
      const color = styleObj.color || '';
      return color ? `${lineType} / ${color}` : lineType;
    } catch (_error) {
      return '';
    }
  }

  private formatTime(timestamp: number): string {
    if (!Number.isFinite(timestamp) || timestamp <= 0) {
      return '';
    }
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    const hour = `${date.getHours()}`.padStart(2, '0');
    const minute = `${date.getMinutes()}`.padStart(2, '0');
    return `${year}-${month}-${day} ${hour}:${minute}`;
  }

  private formatRecordForShare(record: UnifiedAnnotationRecord, index: number): string {
    const lines: string[] = [];
    lines.push(`${index + 1}. [${this.getTypeLabel(record.annotationType)}] ${this.getAnchorLabel(record)}`);

    if (record.title && record.title.trim().length > 0) {
      lines.push(`标记：${record.title.trim()}`);
    }
    if (record.quoteText && record.quoteText.trim().length > 0) {
      lines.push(`摘录：${record.quoteText.trim()}`);
    }
    if (record.textContent && record.textContent.trim().length > 0) {
      lines.push(`想法：${record.textContent.trim()}`);
    }
    if (record.annotationType === UnifiedAnnotationType.HIGHLIGHT) {
      const styleLabel = this.getHighlightStyleLabel(record);
      if (styleLabel.length > 0) {
        lines.push(`样式：${styleLabel}`);
      }
    }
    return lines.join('\n');
  }

  private async copySelectedRecords(): Promise<void> {
    if (this.selectedRecordIds.length <= 0) {
      promptAction.showToast({ message: '请先选择摘录', duration: 1500 });
      return;
    }
    const selected = this.visibleRecords.filter((record: UnifiedAnnotationRecord) =>
      this.selectedRecordIds.includes(record.id)
    );
    if (selected.length <= 0) {
      promptAction.showToast({ message: '没有可复制的摘录', duration: 1500 });
      return;
    }

    const mergedText = selected.map((record: UnifiedAnnotationRecord, index: number) =>
      this.formatRecordForShare(record, index)
    ).join('\n\n');

    logger.info(TAG, `开始拼接复制摘录: selected=${selected.length}`);
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, mergedText);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(pasteData);
      promptAction.showToast({ message: `已复制 ${selected.length} 条摘录`, duration: 1500 });
      logger.info(TAG, `拼接复制成功: selected=${selected.length}, length=${mergedText.length}`);
    } catch (error) {
      logger.error(TAG, `复制摘录失败: ${String(error)}`);
      promptAction.showToast({ message: '复制失败', duration: 1500 });
    }
  }

  @Builder
  buildFilterButton(label: string, value: AnnotationFilterType) {
    Button(label)
      .fontSize(13)
      .fontFamily(this.appFontFamily)
      .fontColor(this.filterType === value ? '#2563EB' : $r('app.color.text_secondary'))
      .backgroundColor(this.filterType === value ? 'rgba(37,99,235,0.15)' : 'rgba(120,120,120,0.12)')
      .borderRadius(14)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .onClick(() => this.onFilterTypeChange(value))
  }

  @Builder
  buildRecordCard(record: UnifiedAnnotationRecord) {
    Column({ space: 8 }) {
      Row() {
        Text(this.getTypeLabel(record.annotationType))
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor('#2563EB')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor('rgba(37,99,235,0.14)')
          .borderRadius(10)

        if (record.annotationType === UnifiedAnnotationType.HIGHLIGHT) {
          if (this.getHighlightStyleLabel(record).length > 0) {
            Text(this.getHighlightStyleLabel(record))
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.text_secondary'))
              .margin({ left: 8 })
          }
        }

        Blank()

        Text(this.formatTime(record.createdAt))
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))

        Button(this.isSelected(record.id) ? '取消' : '选择')
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(this.isSelected(record.id) ? '#FFFFFF' : $r('app.color.text_secondary'))
          .backgroundColor(this.isSelected(record.id) ? '#2563EB' : 'rgba(120,120,120,0.18)')
          .borderRadius(10)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .margin({ left: 8 })
          .onClick(() => this.toggleSelection(record.id))
      }
      .width('100%')

      Text(this.getPrimaryText(record))
        .fontSize(15)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_primary'))
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      if (this.getSecondaryText(record).length > 0) {
        Text(this.getSecondaryText(record))
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      Text(this.getAnchorLabel(record))
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .borderRadius(14)
    .backgroundColor(this.themeManager.getGlassBackgroundResource())
    .border({ width: 1, color: 'rgba(120,120,120,0.18)' })
  }

  build() {
    HdsNavDestination() {
      Column({ space: 12 }) {
        // 内容元信息：用于补充导航栏主标题以外的上下文（内容类型 + 内容标题）
        Text(`${this.getContentTypeLabel(this.contentType)} · ${this.contentTitle}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding({ left: 12, right: 12, top: 8 })

        // 筛选区：快速切换书签/划线/想法视图
        Row({ space: 8 }) {
          this.buildFilterButton('全部', 'all')
          this.buildFilterButton('书签', 'bookmark')
          this.buildFilterButton('划线', 'highlight')
          this.buildFilterButton('想法', 'thought')
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 4 })

        Row() {
          Text(`已选 ${this.selectedRecordIds.length} 项`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor($r('app.color.text_secondary'))

          Blank()

          Button('全选')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor('rgba(120,120,120,0.15)')
            .borderRadius(10)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .onClick(() => this.toggleSelectAllVisible())

          Button('拼接复制')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
            .backgroundColor('#2563EB')
            .borderRadius(10)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .margin({ left: 8 })
            .onClick(() => {
              this.copySelectedRecords();
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12 })

        // 主体区：按状态切换为加载态、空态或数据列表
        if (this.isLoading) {
          Column({ space: 10 }) {
            LoadingProgress()
              .width(30)
              .height(30)
              .color($r('app.color.accent_primary'))
            Text('正在加载摘录...')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.visibleRecords.length <= 0) {
          Column({ space: 10 }) {
            Text('当前筛选下暂无摘录')
              .fontSize(15)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 10 }) {
              ForEach(this.visibleRecords, (record: UnifiedAnnotationRecord) => {
                this.buildRecordCard(record)
              }, (record: UnifiedAnnotationRecord) => record.id)
            }
            .width('100%')
            .padding({ left: 12, right: 12, bottom: 16 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.settings_panel_background'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .titleBar({
      content: {
        title: {
          mainTitle: '摘录中心'
        }
      }
    })
    .backgroundColor(Color.Transparent)
    .onReady((context: NavDestinationContext) => {
      // 页面初始化：绑定路径上下文，解析参数并触发一次数据加载
      logger.info(TAG, 'HdsNavDestination.onReady: 初始化摘录中心页面');
      this.pathStack = context.pathStack;
      const params = this.parsePageParams(context);
      if (!params || !params.contentId) {
        logger.warn(TAG, '页面初始化失败: 缺少必要参数 contentId');
        this.contentId = '';
        this.contentTitle = '摘录中心';
        this.records = [];
        this.visibleRecords = [];
        this.selectedRecordIds = [];
        this.isLoading = false;
        promptAction.showToast({ message: '摘录参数缺失', duration: 1500 });
        return;
      }
      this.contentType = params.contentType;
      this.contentId = params.contentId;
      this.contentTitle = params.contentTitle && params.contentTitle.trim().length > 0
        ? params.contentTitle
        : this.getContentTypeLabel(params.contentType);
      logger.info(TAG, `页面参数绑定完成: contentType=${this.contentType}, contentId=${this.contentId}, contentTitle=${this.contentTitle}`);
      this.loadAnnotations();
    })
    .onBackPressed(() => {
      logger.info(TAG, '触发返回: AnnotationCenterPage.onBackPressed');
      this.pathStack.pop();
      return true;
    })
  }
}
