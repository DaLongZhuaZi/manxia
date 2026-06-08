// 文件路径: entry/src/main/ets/pages/MangaFeedbackPage.ets
/**
 * 漫画问题反馈页面
 * 允许用户报告漫画相关问题，如错误、缺失章节、质量问题等
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
// 已弃用自定义 AnimatedButton，改用原生 ArkUI Button
import { logger } from '../Utils/Logger';
import { PageLifecycleManager } from '../Framework/Lifecycle';

const TAG = 'MangaFeedbackPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

// 问题类型枚举
enum ReportType {
  CHAPTER_MISSING = 'chapter_missing',
  IMAGE_ERROR = 'image_error',
  WRONG_ORDER = 'wrong_order',
  QUALITY_ISSUE = 'quality_issue',
  OTHER = 'other'
}

interface FeedbackReportRecord {
  version: number;
  id: string;
  createdAt: string;
  mangaTitle: string;
  chapterTitle: string;
  reportType: ReportType;
  reportTypeText: string;
  description: string;
  contactInfo: string;
  source: string;
}

// 使用NavDestinationContext官方类型
// @kit.ArkUI提供的NavDestinationContext已包含必要的类型定义

@Component
struct MangaFeedbackPage {
  @State pathStack: NavPathStack = new NavPathStack();
  private scroller: Scroller = new Scroller();

  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'MangaFeedbackPage';

  // 报告内容
  @State mangaTitle: string = '';
  @State chapterTitle: string = '';
  @State reportType: ReportType = ReportType.CHAPTER_MISSING;
  @State description: string = '';
  @State contactInfo: string = '';
  @State isSubmitting: boolean = false;
  @State lastSavedReportPath: string = '';
  @State lastSavedReportText: string = '';
  private feedbackSequence: number = 0;

  onPageShow(): void {
    try {
      const stack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (stack) {
        this.pathStack = stack;
        logger.debug(TAG, '✅ 成功获取GlobalNavStack');
      }
    } catch (err) {
      logger.error(TAG, 'AppStorage.get 异常', String(err));
    }
  }

  onReady(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (newTheme: ThemeType) => {
      logger.info(TAG, `主题切换到: ${newTheme}`);
    });
  }

  private lifecycle = new PageLifecycleManager('MangaFeedbackPage', { enableDebug: true });

  aboutToDisappear(): void {
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
  }

  /**
   * 提交报告
   */
  private async submitReport(): Promise<void> {
    if (this.mangaTitle.trim().length === 0) {
      logger.warn(TAG, '漫画标题不能为空');
      this.showToast('请输入漫画标题');
      return;
    }

    if (this.description.trim().length < 10) {
      logger.warn(TAG, '问题描述至少10个字符');
      this.showToast('问题描述至少需要 10 个字符');
      return;
    }

    this.isSubmitting = true;
    try {
      logger.info(TAG, '提交报告', `漫画: ${this.mangaTitle}, 类型: ${this.reportType}`);

      const record = this.buildFeedbackRecord();
      const reportText = this.formatFeedbackReport(record);
      const reportJson = JSON.stringify(record, null, 2);
      const savedPath = await this.saveFeedbackReport(record.id, reportJson);
      this.lastSavedReportPath = savedPath;
      this.lastSavedReportText = reportText;

      logger.info(TAG, `报告已保存到本地: ${savedPath}`);
      this.showToast('反馈已保存到本地');
      
      // 清空表单
      this.resetForm();
      this.showSavedFeedbackActions(savedPath, reportText);
    } catch (error) {
      logger.error(TAG, '提交报告失败', String(error));
      this.showToast('保存反馈失败，请稍后重试');
    } finally {
      this.isSubmitting = false;
    }
  }

  private buildFeedbackRecord(): FeedbackReportRecord {
    this.feedbackSequence += 1;
    const createdAt = new Date().toISOString();
    const recordId = `${Date.now()}_${this.feedbackSequence}`;
    return {
      version: 1,
      id: recordId,
      createdAt,
      mangaTitle: this.mangaTitle.trim(),
      chapterTitle: this.chapterTitle.trim(),
      reportType: this.reportType,
      reportTypeText: this.getReportTypeText(this.reportType),
      description: this.description.trim(),
      contactInfo: this.contactInfo.trim(),
      source: 'MangaFeedbackPage'
    };
  }

  private formatFeedbackReport(record: FeedbackReportRecord): string {
    const lines: string[] = [
      '漫匣问题反馈',
      `反馈编号：${record.id}`,
      `提交时间：${record.createdAt}`,
      `漫画标题：${record.mangaTitle}`,
      `章节标题：${record.chapterTitle.length > 0 ? record.chapterTitle : '未填写'}`,
      `问题类型：${record.reportTypeText}`,
      `联系方式：${record.contactInfo.length > 0 ? record.contactInfo : '未填写'}`,
      '',
      '问题描述：',
      record.description
    ];
    return lines.join('\n');
  }

  private async saveFeedbackReport(recordId: string, reportJson: string): Promise<string> {
    const hostContext = this.getUIContext().getHostContext();
    if (!hostContext) {
      throw new Error('无法获取页面上下文');
    }
    const abilityContext = hostContext as common.UIAbilityContext;
    const feedbackDir = `${abilityContext.filesDir}/feedback`;
    await this.ensureDirectoryExists(feedbackDir);
    const safeRecordId = this.sanitizeFileName(recordId);
    const targetPath = `${feedbackDir}/manga_feedback_${safeRecordId}.json`;
    await this.writeTextFile(targetPath, reportJson);
    return targetPath;
  }

  private sanitizeFileName(value: string): string {
    return value.replace(/[\\/:*?"<>|.\s]+/g, '_');
  }

  private async ensureDirectoryExists(path: string): Promise<void> {
    const exists = await fileIo.access(path);
    if (exists) {
      const stat = await fileIo.stat(path);
      if (!stat.isDirectory()) {
        throw new Error(`反馈保存路径已存在但不是目录: ${path}`);
      }
      return;
    }
    try {
      await fileIo.mkdir(path, true);
    } catch (error) {
      const errorMessage = String(error);
      if (errorMessage.indexOf('File exists') >= 0) {
        return;
      }
      throw error as Error;
    }
  }

  private async writeTextFile(path: string, content: string): Promise<void> {
    const encoder = new util.TextEncoder();
    const contentBytes = encoder.encodeInto(content);
    const contentBuffer = this.copyUint8ArrayToBuffer(contentBytes);
    const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, contentBuffer);
    } finally {
      await fileIo.close(file);
    }
  }

  private copyUint8ArrayToBuffer(source: Uint8Array): ArrayBuffer {
    const copy = new Uint8Array(source.byteLength);
    copy.set(source);
    return copy.buffer;
  }

  private async copyTextToClipboard(text: string, successMessage: string): Promise<boolean> {
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(pasteData);
      this.showToast(successMessage);
      return true;
    } catch (error) {
      logger.error(TAG, `复制反馈失败: ${String(error)}`);
      this.showToast('复制失败');
      return false;
    }
  }

  private async shareFeedbackBySystem(text: string, savedPath: string): Promise<void> {
    const safeText = text.trim();
    if (safeText.length <= 0) {
      this.showToast('反馈内容为空');
      return;
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.PLAIN_TEXT,
        content: safeText,
        title: '漫匣问题反馈',
        description: `本地反馈文件：${savedPath}`
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      await controller.show(context, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE
      });
      logger.info(TAG, `反馈系统分享已打开: ${savedPath}`);
    } catch (error) {
      logger.error(TAG, `反馈系统分享失败: ${String(error)}`);
      this.showToast('系统分享失败，已复制到剪贴板');
      await this.copyTextToClipboard(safeText, '反馈内容已复制');
    }
  }

  private showSavedFeedbackActions(savedPath: string, reportText: string): void {
    this.getUIContext().getPromptAction().showActionMenu({
      title: '反馈已保存',
      buttons: [
        { text: '复制反馈内容', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '系统分享反馈', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '返回上一页', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '留在页面', color: $r('sys.color.ohos_id_color_text_primary') }
      ]
    }).then(async (result: promptAction.ActionMenuSuccessResponse) => {
      if (result.index === 0) {
        await this.copyTextToClipboard(reportText, '反馈内容已复制');
      } else if (result.index === 1) {
        await this.shareFeedbackBySystem(reportText, savedPath);
      } else if (result.index === 2) {
        this.goBack();
      }
    }).catch(() => {});
  }

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({
      message,
      duration: 1800
    });
  }

  /**
   * 重置表单
   */
  private resetForm(): void {
    this.mangaTitle = '';
    this.chapterTitle = '';
    this.reportType = ReportType.CHAPTER_MISSING;
    this.description = '';
    this.contactInfo = '';
  }

  private goBack(): void {
    try {
      this.pathStack.pop();
    } catch (error) {
      logger.error(TAG, '返回失败', String(error));
    }
  }

  /**
   * 获取报告类型文本
   */
  private getReportTypeText(type: ReportType): string {
    switch (type) {
      case ReportType.CHAPTER_MISSING:
        return '章节缺失';
      case ReportType.IMAGE_ERROR:
        return '图片错误';
      case ReportType.WRONG_ORDER:
        return '顺序错误';
      case ReportType.QUALITY_ISSUE:
        return '质量问题';
      case ReportType.OTHER:
        return '其他问题';
      default:
        return '未知';
    }
  }

  /**
   * 构建报告类型选择
   */
  @Builder
  buildReportTypeSelection() {
    Column({ space: 12 }) {
      Text('问题类型')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Row({ space: 8 }) {
        Button({ stateEffect: true }) {
          Text('章节缺失')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
        }
          .width('100%')
          .height(36)
          .backgroundColor(
            this.reportType === ReportType.CHAPTER_MISSING
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
          )
          .borderRadius(8)
          .onClick(() => {
            this.reportType = ReportType.CHAPTER_MISSING;
          })

        Button({ stateEffect: true }) {
          Text('图片错误')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
        }
          .width('100%')
          .height(36)
          .backgroundColor(
            this.reportType === ReportType.IMAGE_ERROR
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
          )
          .borderRadius(8)
          .onClick(() => {
            this.reportType = ReportType.IMAGE_ERROR;
          })

        Button({ stateEffect: true }) {
          Text('顺序错误')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
        }
          .width('100%')
          .height(36)
          .backgroundColor(
            this.reportType === ReportType.WRONG_ORDER
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
          )
          .borderRadius(8)
          .onClick(() => {
            this.reportType = ReportType.WRONG_ORDER;
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        Button({ stateEffect: true }) {
          Text('质量问题')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
        }
          .width('100%')
          .height(36)
          .backgroundColor(
            this.reportType === ReportType.QUALITY_ISSUE
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
          )
          .borderRadius(8)
          .onClick(() => {
            this.reportType = ReportType.QUALITY_ISSUE;
          })

        Button({ stateEffect: true }) {
          Text('其他问题')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
        }
          .width('100%')
          .height(36)
          .backgroundColor(
            this.reportType === ReportType.OTHER
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
          )
          .borderRadius(8)
          .onClick(() => {
            this.reportType = ReportType.OTHER;
          })

        Blank().layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
  }

  /**
   * 构建表单区域
   */
  @Builder
  buildForm() {
    Column({ space: 16 }) {
      // 漫画标题
      Column({ space: 8 }) {
        Text('漫画标题 *')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .alignSelf(ItemAlign.Start)

        TextInput({ placeholder: '请输入漫画标题', text: this.mangaTitle })
          .width('100%')
          .height(44)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .onChange((value: string) => {
            this.mangaTitle = value;
          })
      }

      // 章节标题（可选）
      Column({ space: 8 }) {
        Text('章节标题')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .alignSelf(ItemAlign.Start)

        TextInput({ placeholder: '请输入章节标题（可选）', text: this.chapterTitle })
          .width('100%')
          .height(44)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .onChange((value: string) => {
            this.chapterTitle = value;
          })
      }

      // 问题描述
      Column({ space: 8 }) {
        Text('问题描述 *')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .alignSelf(ItemAlign.Start)

        TextArea({ placeholder: '请详细描述您遇到的问题...', text: this.description })
          .width('100%')
          .height(120)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .onChange((value: string) => {
            this.description = value;
          })

        Text(`${this.description.length} / 500`)
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .alignSelf(ItemAlign.End)
      }

      // 联系方式（可选）
      Column({ space: 8 }) {
        Text('联系方式')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .alignSelf(ItemAlign.Start)

        TextInput({ placeholder: '请输入您的联系方式（可选）', text: this.contactInfo })
          .width('100%')
          .height(44)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .onChange((value: string) => {
            this.contactInfo = value;
          })

        Text('填写联系方式可以让我们更好地跟进您的反馈')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .opacity(0.7)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
  }

  /**
   * 构建操作按钮
   */
  @Builder
  buildActionButtons() {
    Row({ space: 12 }) {
      Column() {
        Button({ stateEffect: true }) {
          Text('重置')
            .fontSize(16)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
          .width('100%')
          .height(44)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
          .borderRadius(12)
          .onClick(() => {
            this.resetForm();
          })
      }.width('30%')

      Column() {
        Button({ stateEffect: true }) {
          Text(this.isSubmitting ? '提交中...' : '提交报告')
            .fontSize(16)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
          .width('100%')
          .height(44)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .borderRadius(12)
          .onClick(() => {
            if (!this.isSubmitting) {
              this.submitReport().catch((error: Error) => {
                logger.error(TAG, '提交报告异常', error.message);
              });
            }
          })
      }.layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 16, bottom: 24 })
  }

  build() {
    HdsNavDestination() {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        
        Scroll(this.scroller) {
          Column({ space: 16 }) {
            Blank().height(TITLE_BAR_HEIGHT_MINI)

            // 提示信息
            Column({ space: 8 }) {
              Text('📝 问题反馈')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .alignSelf(ItemAlign.Start)

              Text('如果您在使用过程中遇到任何问题，请通过此表单告诉我们。我们会尽快处理您的反馈。')
                .fontSize(14)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .lineHeight(20)
            }
            .width('100%')
            .padding(16)

            this.buildReportTypeSelection()
            this.buildForm()
            this.buildActionButtons()
          }
          .width('100%')
          .padding({ left: 20, right: 20, bottom: 40 })
        }
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Auto)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }
    }
    .titleBar({
      padding: {
        start: LengthMetrics.vp(16),
        end: LengthMetrics.vp(16)
      },
      style: {
        originalStyle: {
          backgroundStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme) },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        }
      },
      content: {
        title: { mainTitle: '问题反馈' }
      }
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.onPageShow();
      this.onReady();
    })
    .backgroundColor(Color.Transparent)
  }
}

export { MangaFeedbackPage }
