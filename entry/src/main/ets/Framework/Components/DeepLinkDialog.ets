/**
 * 深度链接跳转对话框
 * 通过 DeepLinkDialogManager.show() 从任何页面调用
 */

import { ThemeAwareState, ThemeAwareHelper } from './ThemeAware';
import { DeepLinkRouter, DeepLinkResult } from '../Utils/DeepLinkRouter';
import { DialogSurfaceStyleHelper } from './DialogSurfaceStyleHelper';
import { logger } from '../../Utils/Logger';
import { promptAction } from '@kit.ArkUI';

const TAG = 'DeepLinkDialog';

@CustomDialog
export struct DeepLinkDialog {
  controller: CustomDialogController;
  @Prop themeState: ThemeAwareState;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  @State private linkInput: string = '';
  @State private parseResult: string = '';
  @State private isValidLink: boolean = false;
  @State private isNavigating: boolean = false;

  private router: DeepLinkRouter = DeepLinkRouter.getInstance();
  private parsedResult: DeepLinkResult | null = null;
  onNavigate: () => void = () => {};
  onCancel: () => void = () => {};

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message, duration: 2000 });
  }

  private handleInputChange(value: string): void {
    this.linkInput = value.trim();

    if (this.linkInput.length === 0) {
      this.parseResult = '';
      this.isValidLink = false;
      this.parsedResult = null;
      return;
    }

    if (!this.router.isManxiaUri(this.linkInput)) {
      this.parseResult = '请输入 manxia:// 开头的链接';
      this.isValidLink = false;
      this.parsedResult = null;
      return;
    }

    const result: DeepLinkResult | null = this.router.parse(this.linkInput);
    if (result) {
      this.parsedResult = result;
      this.parseResult = this.router.formatResult(result);
      this.isValidLink = true;
    } else {
      this.parseResult = '无法解析此链接，请检查格式';
      this.isValidLink = false;
      this.parsedResult = null;
    }
  }

  private handleNavigate(): void {
    if (!this.isValidLink || !this.linkInput) {
      this.showToast('请输入有效的链接');
      return;
    }

    this.isNavigating = true;
    const success: boolean = this.router.navigate(this.linkInput);

    if (success) {
      this.showToast('正在跳转...');
      this.onNavigate();
      this.controller.close();
    } else {
      this.showToast('跳转失败，请检查链接');
      this.isNavigating = false;
    }
  }

  build() {
    Column({ space: 20 }) {
      Text('链接跳转')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      Text('输入 manxia:// 协议链接，快速跳转到指定内容')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')

      TextInput({ placeholder: 'manxia://search/pixiv?type=id&query=12345', text: this.linkInput })
        .width('100%')
        .onChange((value: string) => {
          this.handleInputChange(value);
        })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
        .borderRadius(8)

      if (this.linkInput.length > 0) {
        Column({ space: 4 }) {
          Row({ space: 8 }) {
            Text(this.isValidLink ? '✓' : '✗')
              .fontSize(14)
              .fontColor(this.isValidLink ? '#98FB98' : '#FF6B6B')

            Text(this.isValidLink ? '链接格式正确' : '链接格式错误')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(this.isValidLink ?
                ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) :
                '#FF6B6B')
          }
          .width('100%')

          if (this.parseResult.length > 0) {
            Text(this.parseResult)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .width('100%')
          }
        }
        .width('100%')
        .padding(12)
        .backgroundColor(this.isValidLink ?
          ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme) :
          'rgba(255, 107, 107, 0.08)')
        .borderRadius(8)
      }

      Column({ space: 4 }) {
        Text('支持的链接格式:')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .width('100%')

        Text('manxia://search/{图源}?type={类型}&query={内容}')
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .width('100%')
      }
      .width('100%')

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .borderRadius(8)
          .onClick(() => {
            this.onCancel();
            this.controller.close();
          })

        Button('跳转')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .fontColor(Color.White)
          .borderRadius(8)
          .enabled(this.isValidLink && !this.isNavigating)
          .opacity(this.isValidLink && !this.isNavigating ? 1.0 : 0.5)
          .onClick(() => {
            this.handleNavigate();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(16)
  }
}

/**
 * 深度链接对话框管理器
 * 从任何页面调用 DeepLinkDialogManager.show() 即可打开
 */
export class DeepLinkDialogManager {
  private static currentController: CustomDialogController | undefined = undefined;

  public static show(): void {
    if (DeepLinkDialogManager.currentController) {
      try {
        DeepLinkDialogManager.currentController.close();
      } catch (err) {
        logger.warn(TAG, `关闭旧对话框失败: ${String(err)}`);
      }
      DeepLinkDialogManager.currentController = undefined;
    }

    const themeState: ThemeAwareState = new ThemeAwareState();

    let controller: CustomDialogController | null = null;
    controller = new CustomDialogController({
      builder: DeepLinkDialog({
        themeState: themeState,
        onNavigate: () => {
          logger.info(TAG, '深度链接跳转执行');
        },
        onCancel: () => {
          logger.info(TAG, '深度链接对话框取消');
        }
      }),
      autoCancel: false,
      customStyle: true,
      alignment: DialogAlignment.Center
    });

    DeepLinkDialogManager.currentController = controller;
    controller.open();
    logger.info(TAG, '深度链接对话框已打开');
  }
}
