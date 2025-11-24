// 文件路径: entry/src/main/ets/Framework/Components/EBookMetadataDialog.ets
/**
 * 电子书元数据补充对话框
 * 用于在电子书导入时补充缺失的关键信息
 */

import { EBookMetadata } from '../../Models/EBookModels';
import { ThemeAwareState, ThemeAwareHelper } from './ThemeAware';
import { logger } from '../../Utils/Logger';

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
      // 标题
      Text('补充电子书信息')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')
        .textAlign(TextAlign.Center)

      // 提示文本
      Text('请填写电子书的基本信息，标有*的为必填项')
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')

      Scroll() {
        Column({ space: 12 }) {
          // 书名 *
          this.buildInputField('书名 *', this.title, (value: string) => {
            this.title = value;
          }, 'placeholder_book_title')

          // 作者 *
          this.buildInputField('作者 *', this.author, (value: string) => {
            this.author = value;
          }, 'placeholder_author')

          // 简介
          this.buildTextAreaField('简介', this.description, (value: string) => {
            this.description = value;
          })

          // 出版社
          this.buildInputField('出版社', this.publisher, (value: string) => {
            this.publisher = value;
          }, 'placeholder_publisher')

          // 出版日期
          this.buildInputField('出版日期', this.publishDate, (value: string) => {
            this.publishDate = value;
          }, 'placeholder_publish_date')

          // ISBN
          this.buildInputField('ISBN', this.isbn, (value: string) => {
            this.isbn = value;
          }, 'placeholder_isbn')

          // 标签（逗号分隔）
          this.buildInputField('标签（逗号分隔）', this.tagsText, (value: string) => {
            this.tagsText = value;
          }, 'placeholder_tags')
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
}

