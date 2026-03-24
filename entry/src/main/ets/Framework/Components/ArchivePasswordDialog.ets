import { ThemeAwareState, ThemeAwareHelper } from './ThemeAware';
import { promptAction } from '@kit.ArkUI';

@CustomDialog
export struct ArchivePasswordDialog {
  controller: CustomDialogController;
  @Prop themeState: ThemeAwareState;
  @Prop fileName: string = '';
  @Prop initialPassword: string = '';
  @Prop errorMessage: string = '';
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  @State private password: string = '';
  @State private showPassword: boolean = false;

  onConfirm: (password: string) => void = () => {};
  onCancel: () => void = () => {};

  aboutToAppear(): void {
    this.password = this.initialPassword;
  }

  private showToast(message: string): void {
    promptAction.showToast({ message, duration: 2000 });
  }

  build() {
    Column({ space: 16 }) {
      Text('输入压缩包密码')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      Column({ space: 6 }) {
        Text('文件')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')

        Text(this.fileName || '未知文件')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(8)

      if (this.errorMessage && this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor('#E57373')
          .width('100%')
      }

      Column({ space: 8 }) {
        Text('密码')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width('100%')

        Row({ space: 8 }) {
          TextInput({ text: this.password, placeholder: '请输入压缩包密码' })
            .type(this.showPassword ? InputType.Normal : InputType.Password)
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(8)
            .padding({ left: 12, right: 12 })
            .height(42)
            .layoutWeight(1)
            .onChange((value: string) => {
              this.password = value;
            })

          Button(this.showPassword ? '隐藏' : '显示')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
            .borderRadius(8)
            .height(42)
            .onClick(() => {
              this.showPassword = !this.showPassword;
            })
        }
        .width('100%')
      }
      .width('100%')

      Text('如果这是同一批加密压缩包，后续会优先复用你刚输入的密码。')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
          .borderRadius(8)
          .onClick(() => {
            this.onCancel();
            this.controller.close();
          })

        Button('继续')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontFamily(this.appFontFamily)
          .fontColor(Color.White)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .borderRadius(8)
          .onClick(() => {
            const finalPassword = this.password.trim();
            if (!finalPassword) {
              this.showToast('请输入密码');
              return;
            }
            this.onConfirm(finalPassword);
            this.controller.close();
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

export function showArchivePasswordDialog(
  themeState: ThemeAwareState,
  fileName: string,
  initialPassword: string = '',
  errorMessage: string = ''
): Promise<string | null> {
  return new Promise((resolve) => {
    let controller: CustomDialogController | null = null;
    controller = new CustomDialogController({
      builder: ArchivePasswordDialog({
        themeState: themeState,
        fileName: fileName,
        initialPassword: initialPassword,
        errorMessage: errorMessage,
        onConfirm: (password: string) => {
          resolve(password);
        },
        onCancel: () => {
          resolve(null);
        }
      }),
      autoCancel: false,
      customStyle: true,
      alignment: DialogAlignment.Center
    });

    controller.open();
  });
}
