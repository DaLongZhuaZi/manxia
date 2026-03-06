// 文件路径: entry/src/main/ets/pages/MangaFeedbackPage.ets
/**
 * 漫画问题反馈页面
 * 允许用户报告漫画相关问题，如错误、缺失章节、质量问题等
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
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
    if (this.mangaTitle.length === 0) {
      logger.warn(TAG, '漫画标题不能为空');
      return;
    }

    if (this.description.length < 10) {
      logger.warn(TAG, '问题描述至少10个字符');
      return;
    }

    this.isSubmitting = true;
    try {
      logger.info(TAG, '提交报告', `漫画: ${this.mangaTitle}, 类型: ${this.reportType}`);

      // TODO: 实现报告提交逻辑（发送到服务器或保存到本地）
      // 模拟提交延迟
      await new Promise<void>((resolve) => setTimeout(resolve, 1500));

      logger.info(TAG, '报告提交成功');
      
      // 清空表单
      this.resetForm();
      
      // 返回上一页
      this.goBack();
    } catch (error) {
      logger.error(TAG, '提交报告失败', String(error));
    } finally {
      this.isSubmitting = false;
    }
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
