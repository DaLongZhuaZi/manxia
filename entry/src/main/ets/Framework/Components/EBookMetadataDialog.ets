// 文件路径: entry/src/main/ets/Framework/Components/EBookMetadataDialog.ets
/**
 * 电子书元数据补充对话框
 * 用于在电子书导入时补充缺失的关键信息
 */

import { EBookMetadata } from '../../Models/EBookModels';
import { ThemeAwareState, ThemeAwareHelper } from './ThemeAware';
import { logger } from '../../Utils/Logger';
import { ScraperDialog, ScraperDialogConfig, ScraperDialogResult } from './ScraperDialog';
import { ScraperContentType } from '../Scraper/ScraperTypes';

const TAG = 'EBookMetadataDialog';

/**
 * 电子书元数据补充对话框
 */
@CustomDialog
export struct EBookMetadataDialog {
  controller: CustomDialogController;
  @Prop themeState: ThemeAwareState;
  @Prop initialMetadata: EBookMetadata;
  // 回调函数不能使用@Prop装饰器，应使用普通属性
  onConfirm: (metadata: EBookMetadata) => void = (metadata: EBookMetadata) => {};
  onCancel: () => void = () => {};

  // 表单状态
  @State title: string = '';
  @State author: string = '';
  @State description: string = '';
  @State publisher: string = '';
  @State publishDate: string = '';
  @State isbn: string = '';
  @State tagsText: string = '';

  // 刮削对话框控制器
  private scraperDialogController: CustomDialogController | null = null;

  aboutToAppear(): void {
    // 初始化表单字段
    this.title = this.initialMetadata.title || '';
    this.author = this.initialMetadata.author || '';
    this.description = this.initialMetadata.description || '';
    this.publisher = this.initialMetadata.publisher || '';
    this.publishDate = this.initialMetadata.publishDate || '';
    this.isbn = this.initialMetadata.isbn || '';
    this.tagsText = this.initialMetadata.tags.join(', ');
  }

  build() {
    Column({ space: 16 }) {
      // 标题栏
      Row() {
        Text('补充电子书信息')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Blank()

        // 刮削按钮
        Row({ space: 4 }) {
          Image($r('app.media.ic_scraper'))
            .width(18)
            .height(18)
            .fillColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

          Text('刮削')
            .fontSize(13)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        }
        .padding({ left: 10, right: 12, top: 6, bottom: 6 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15')
        .borderRadius(16)
        .onClick(() => {
          this.openScraperDialog();
        })
      }
      .width('100%')

      // 提示文本
      Text('请填写电子书的基本信息，标有*的为必填项，点击“刮削”可自动填充')
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')

      Scroll() {
        Column({ space: 12 }) {
          // 书名 * - 内联定义以确保响应式更新
          Column({ space: 4 }) {
            Text('书名 *')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .width('100%')

            TextInput({ text: this.title, placeholder: '请输入书名' })
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .borderRadius(6)
              .padding({ left: 12, right: 12 })
              .height(40)
              .width('100%')
              .onChange((value: string) => {
                this.title = value;
              })
          }
          .width('100%')

          // 作者 * - 内联定义以确保响应式更新
          Column({ space: 4 }) {
            Text('作者 *')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .width('100%')

            TextInput({ text: this.author, placeholder: '请输入作者' })
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .borderRadius(6)
              .padding({ left: 12, right: 12 })
              .height(40)
              .width('100%')
              .onChange((value: string) => {
                this.author = value;
              })
          }
          .width('100%')

          // 简介 - 内联定义以确保响应式更新
          Column({ space: 4 }) {
            Text('简介')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .width('100%')

            TextArea({ text: this.description, placeholder: '请输入简介...' })
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .borderRadius(6)
              .padding(12)
              .height(100)
              .width('100%')
              .onChange((value: string) => {
                this.description = value;
              })
          }
          .width('100%')

          // 出版社 - 内联定义以确保响应式更新
          Column({ space: 4 }) {
            Text('出版社')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .width('100%')

            TextInput({ text: this.publisher, placeholder: '请输入出版社' })
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .borderRadius(6)
              .padding({ left: 12, right: 12 })
              .height(40)
              .width('100%')
              .onChange((value: string) => {
                this.publisher = value;
              })
          }
          .width('100%')

          // 出版日期 - 内联定义以确保响应式更新
          Column({ space: 4 }) {
            Text('出版日期')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .width('100%')

            TextInput({ text: this.publishDate, placeholder: '例如: 2023-01-01' })
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .borderRadius(6)
              .padding({ left: 12, right: 12 })
              .height(40)
              .width('100%')
              .onChange((value: string) => {
                this.publishDate = value;
              })
          }
          .width('100%')

          // ISBN - 内联定义以确保响应式更新
          Column({ space: 4 }) {
            Text('ISBN')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .width('100%')

            TextInput({ text: this.isbn, placeholder: '请输入ISBN' })
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .borderRadius(6)
              .padding({ left: 12, right: 12 })
              .height(40)
              .width('100%')
              .onChange((value: string) => {
                this.isbn = value;
              })
          }
          .width('100%')

          // 标签（逗号分隔） - 内联定义以确保响应式更新
          Column({ space: 4 }) {
            Text('标签（逗号分隔）')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .width('100%')

            TextInput({ text: this.tagsText, placeholder: '例如: 科幻, 悬疑, 推理' })
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .borderRadius(6)
              .padding({ left: 12, right: 12 })
              .height(40)
              .width('100%')
              .onChange((value: string) => {
                this.tagsText = value;
              })
          }
          .width('100%')
        }
        .width('100%')
      }
      .height(400)
      .width('100%')

      // 操作按钮
      Row({ space: 12 }) {
        Button('取消')
          .fontSize(16)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
          .borderRadius(8)
          .height(44)
          .layoutWeight(1)
          .onClick(() => {
            this.onCancel();
            this.controller.close();
          })

        Button('确认')
          .fontSize(16)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .borderRadius(8)
          .height(44)
          .layoutWeight(1)
          .onClick(() => {
            if (this.validateForm()) {
              const metadata: EBookMetadata = {
                title: this.title.trim(),
                author: this.author.trim(),
                description: this.description.trim(),
                publisher: this.publisher.trim(),
                publishDate: this.publishDate.trim(),
                isbn: this.isbn.trim(),
                language: this.initialMetadata.language,
                coverImagePath: this.initialMetadata.coverImagePath,
                tags: this.parseTags(this.tagsText),
                rating: this.initialMetadata.rating
              };
              this.onConfirm(metadata);
              this.controller.close();
            }
          })
      }
      .width('100%')
    }
    .width('90%')
    .padding(20)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({
      width: 1,
      color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
    })
  }

  @Builder
  buildInputField(label: string, value: string, onChange: (value: string) => void, placeholder: string) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      TextInput({ text: value, placeholder: placeholder })
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(6)
        .padding({ left: 12, right: 12 })
        .height(40)
        .width('100%')
        .onChange((value: string) => {
          onChange(value);
        })
    }
    .width('100%')
  }

  @Builder
  buildTextAreaField(label: string, value: string, onChange: (value: string) => void) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      TextArea({ text: value, placeholder: '请输入简介...' })
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(6)
        .padding(12)
        .height(100)
        .width('100%')
        .onChange((value: string) => {
          onChange(value);
        })
    }
    .width('100%')
  }

  /**
   * 验证表单
   */
  private validateForm(): boolean {
    if (this.title.trim().length === 0) {
      logger.warn(TAG, '书名不能为空');
      // TODO: 显示错误提示
      return false;
    }

    if (this.author.trim().length === 0) {
      logger.warn(TAG, '作者不能为空');
      // TODO: 显示错误提示
      return false;
    }

    return true;
  }

  /**
   * 解析标签字符串
   */
  private parseTags(tagsText: string): string[] {
    if (!tagsText || tagsText.trim().length === 0) {
      return [];
    }

    return tagsText
      .split(/[,，、]/)
      .map((tag: string) => tag.trim())
      .filter((tag: string) => tag.length > 0);
  }

  /**
   * 打开刮削对话框
   */
  private openScraperDialog(): void {
    const config: ScraperDialogConfig = {
      initialKeyword: this.title || this.initialMetadata.title || '',
      contentType: ScraperContentType.BOOK,
      title: '搜索电子书信息'
    };

    this.scraperDialogController = new CustomDialogController({
      builder: ScraperDialog({
        themeState: this.themeState,
        config: config,
        onConfirm: (result: ScraperDialogResult) => {
          this.applyScraperResult(result);
        },
        onCancel: () => {
          logger.info(TAG, '用户取消刮削');
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true
    });

    this.scraperDialogController.open();
  }

  /**
   * 应用刮削结果
   */
  private applyScraperResult(result: ScraperDialogResult): void {
    const metadata = result.metadata;
    logger.info(TAG, `应用刮削结果: ${metadata.title}`);

    // 应用标题（如果当前为空）
    if (!this.title && metadata.title) {
      this.title = metadata.title;
    }

    // 应用作者
    if (result.applyAuthor && metadata.author) {
      this.author = metadata.author;
    }

    // 应用描述
    if (result.applyDescription && metadata.description) {
      this.description = metadata.description;
    }

    // 应用出版社
    if (result.applyPublisher && metadata.publisher) {
      this.publisher = metadata.publisher;
    }

    // 应用发布日期
    if (metadata.releaseDate) {
      this.publishDate = metadata.releaseDate;
    }

    // 应用标签
    if (result.applyTags && metadata.tags && metadata.tags.length > 0) {
      this.tagsText = metadata.tags.join(', ');
    }

    logger.info(TAG, '刮削结果已应用');
  }
}

