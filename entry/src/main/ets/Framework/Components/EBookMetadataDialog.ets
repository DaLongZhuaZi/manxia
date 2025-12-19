// 文件路径: entry/src/main/ets/Framework/Components/EBookMetadataDialog.ets
/**
 * 电子书元数据补充对话框（增强版）
 * 用于在电子书导入时查看和编辑书籍信息
 * 支持：元数据编辑、自定义封面、章节列表预览
 */

import { EBookMetadata, EBookChapter } from '../../Models/EBookModels';
import { ThemeAwareState, ThemeAwareHelper } from './ThemeAware';
import { logger } from '../../Utils/Logger';
import { ScraperDialog, ScraperDialogConfig, ScraperDialogResult } from './ScraperDialog';
import { ScraperContentType } from '../Scraper/ScraperTypes';
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';

const TAG = 'EBookMetadataDialog';

/**
 * 对话框确认结果
 */
export interface EBookMetadataDialogResult {
  metadata: EBookMetadata;
  customCoverPath?: string;  // 用户选择的自定义封面路径
}

/**
 * 电子书元数据补充对话框
 */
@CustomDialog
export struct EBookMetadataDialog {
  controller: CustomDialogController;
  @Prop themeState: ThemeAwareState;
  @Prop initialMetadata: EBookMetadata;
  @Prop chapters: EBookChapter[] = [];  // 章节列表
  // 回调函数不能使用@Prop装饰器，应使用普通属性
  onConfirm: (result: EBookMetadataDialogResult) => void = (result: EBookMetadataDialogResult) => {};
  onCancel: () => void = () => {};
  onRegenerateCover: (title: string, oldCoverPath: string) => Promise<string> = async () => '';  // 重新生成封面回调

  // 表单状态
  @State title: string = '';
  @State author: string = '';
  @State description: string = '';
  @State publisher: string = '';
  @State publishDate: string = '';
  @State isbn: string = '';
  @State tagsText: string = '';
  
  // 封面相关
  @State coverPath: string = '';
  @State customCoverPath: string = '';  // 用户选择的自定义封面
  @State isRegeneratingCover: boolean = false;  // 是否正在重新生成封面
  @State coverRefreshKey: number = 0;  // 用于强制刷新封面图片
  
  // 当前显示的标签页：'info' | 'chapters'
  @State currentTab: string = 'info';
  
  // 章节列表展开状态
  @State showAllChapters: boolean = false;

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
    this.coverPath = this.initialMetadata.coverImagePath || '';
    
    logger.info(TAG, `对话框初始化: 标题=${this.title}, 作者=${this.author}, 章节数=${this.chapters.length}`);
  }

  build() {
    Column({ space: 12 }) {
      // 标题栏
      Row() {
        Text('确认电子书信息')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Blank()

        // [暂时禁用] 刮削按钮 - 功能暂时关闭，保留逻辑实现
        // Row({ space: 4 }) {
        //   Image($r('app.media.ic_scraper'))
        //     .width(18)
        //     .height(18)
        //     .fillColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        //
        //   Text('刮削')
        //     .fontSize(13)
        //     .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        // }
        // .padding({ left: 10, right: 12, top: 6, bottom: 6 })
        // .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15')
        // .borderRadius(16)
        // .onClick(() => {
        //   this.openScraperDialog();
        // })
      }
      .width('100%')

      // 标签页切换
      Row({ space: 0 }) {
        this.buildTabButton('基本信息', 'info')
        this.buildTabButton(`章节列表 (${this.chapters.length})`, 'chapters')
      }
      .width('100%')
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(8)
      .padding(4)

      // 内容区域
      if (this.currentTab === 'info') {
        this.buildInfoTab()
      } else {
        this.buildChaptersTab()
      }

      // 操作按钮
      Row({ space: 12 }) {
        Button('取消导入')
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

        Button('确认导入')
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
                coverImagePath: this.customCoverPath || this.coverPath || this.initialMetadata.coverImagePath,
                tags: this.parseTags(this.tagsText),
                rating: this.initialMetadata.rating
              };
              const result: EBookMetadataDialogResult = {
                metadata: metadata,
                customCoverPath: this.customCoverPath || undefined
              };
              this.onConfirm(result);
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
   * 构建标签页按钮
   */
  @Builder
  buildTabButton(label: string, tabId: string) {
    Text(label)
      .fontSize(14)
      .fontWeight(this.currentTab === tabId ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.currentTab === tabId 
        ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      .backgroundColor(this.currentTab === tabId 
        ? ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme)
        : Color.Transparent)
      .borderRadius(6)
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .onClick(() => {
        this.currentTab = tabId;
      })
  }
  
  /**
   * 构建基本信息标签页
   */
  @Builder
  buildInfoTab() {
    Scroll() {
      Column({ space: 12 }) {
        // 封面区域
        Row({ space: 16 }) {
          // 封面预览
          Column() {
            if (this.customCoverPath || this.coverPath) {
              Image(this.normalizeCoverPath(this.customCoverPath || this.coverPath) + `?refresh=${this.coverRefreshKey}`)
                .width(80)
                .height(110)
                .objectFit(ImageFit.Cover)
                .borderRadius(4)
            } else {
              // 无封面时使用默认电子书图标
              Image($r('app.media.ebook'))
                .width(80)
                .height(110)
                .objectFit(ImageFit.Cover)
                .borderRadius(4)
            }
          }
          
          // 封面操作按钮
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Button('选择封面')
                .fontSize(12)
                .height(32)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
                .borderRadius(6)
                .onClick(() => {
                  this.selectCustomCover();
                })
              
              Button(this.isRegeneratingCover ? '生成中...' : '重新生成')
                .fontSize(12)
                .height(32)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_secondary', this.themeState.currentTheme))
                .fontColor(Color.White)
                .borderRadius(6)
                .enabled(!this.isRegeneratingCover)
                .onClick(async () => {
                  await this.regenerateCover();
                })
            }
            
            if (this.customCoverPath) {
              Button('清除')
                .fontSize(12)
                .height(32)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .borderRadius(6)
                .onClick(() => {
                  this.customCoverPath = '';
                })
            }
          }
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ bottom: 8 })
        
        // 书名
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

        // 作者
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

        // 简介
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
            .height(80)
            .width('100%')
            .onChange((value: string) => {
              this.description = value;
            })
        }
        .width('100%')

        // 标签
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
    .height(350)
    .width('100%')
  }
  
  /**
   * 构建章节列表标签页
   */
  @Builder
  buildChaptersTab() {
    Column({ space: 8 }) {
      // 章节统计
      Row() {
        Text(`共 ${this.chapters.length} 个章节`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Blank()
        
        if (this.chapters.length > 10) {
          Text(this.showAllChapters ? '收起' : '展开全部')
            .fontSize(13)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .onClick(() => {
              this.showAllChapters = !this.showAllChapters;
            })
        }
      }
      .width('100%')
      
      // 章节列表
      if (this.chapters.length === 0) {
        Column() {
          Text('未检测到章节')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          Text('该电子书可能没有明确的章节划分')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .margin({ top: 4 })
        }
        .width('100%')
        .height(300)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 4 }) {
            ForEach(this.getDisplayChapters(), (chapter: EBookChapter, index: number) => {
              Row() {
                Text(`${index + 1}.`)
                  .fontSize(13)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .width(30)
                
                Text(chapter.title)
                  .fontSize(13)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                
                Text(`${chapter.wordCount}字`)
                  .fontSize(11)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              }
              .width('100%')
              .padding({ left: 8, right: 8, top: 6, bottom: 6 })
              .backgroundColor(index % 2 === 0 
                ? Color.Transparent 
                : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme) + '50')
              .borderRadius(4)
            })
          }
          .width('100%')
        }
        .height(300)
        .width('100%')
      }
    }
    .width('100%')
    .height(350)
  }
  
  /**
   * 获取要显示的章节列表
   */
  private getDisplayChapters(): EBookChapter[] {
    if (this.showAllChapters || this.chapters.length <= 10) {
      return this.chapters;
    }
    return this.chapters.slice(0, 10);
  }
  
  /**
   * 重新生成封面
   */
  private async regenerateCover(): Promise<void> {
    if (this.isRegeneratingCover) {
      return;
    }
    
    this.isRegeneratingCover = true;
    try {
      const oldCoverPath = this.coverPath || this.customCoverPath || '';
      const newCoverPath = await this.onRegenerateCover(this.title, oldCoverPath);
      
      if (newCoverPath && newCoverPath.length > 0) {
        this.coverPath = newCoverPath;
        this.customCoverPath = '';  // 清除自定义封面，使用新生成的封面
        this.coverRefreshKey++;  // 强制刷新封面图片
        logger.info(TAG, `封面重新生成成功: ${newCoverPath}`);
      } else {
        logger.warn(TAG, '封面重新生成失败');
      }
    } catch (error) {
      logger.error(TAG, `重新生成封面失败: ${String(error)}`);
    } finally {
      this.isRegeneratingCover = false;
    }
  }

  /**
   * 选择自定义封面
   */
  private async selectCustomCover(): Promise<void> {
    try {
      const photoPicker = new picker.PhotoViewPicker();
      const selectOptions: picker.PhotoSelectOptions = {
        MIMEType: picker.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      };
      
      const result = await photoPicker.select(selectOptions);
      if (result && result.photoUris && result.photoUris.length > 0) {
        this.customCoverPath = result.photoUris[0];
        logger.info(TAG, `选择了自定义封面: ${this.customCoverPath}`);
      }
    } catch (error) {
      logger.error(TAG, `选择封面失败: ${String(error)}`);
    }
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
   * 规范化封面路径：本地文件添加 file:// 前缀
   */
  private normalizeCoverPath(path: string): string {
    if (!path || path.length === 0) {
      return '';
    }
    // 本地文件路径需要添加 file:// 前缀
    if (path.startsWith('/')) {
      return `file://${path}`;
    }
    return path;
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

