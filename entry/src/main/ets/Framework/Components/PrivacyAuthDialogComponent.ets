// 文件路径: entry/src/main/ets/Framework/Components/PrivacyAuthDialogComponent.ets
// 职责: 隐私模式密码验证对话框组件，从MainMenuPage提取的独立组件

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { SourceDialogScaffold } from './SourceDialogScaffold';
import { DialogSurfaceStyleHelper } from './DialogSurfaceStyleHelper';
import { PrivacyModeManager } from 'manxia_theme/src/main/ets/Framework/Managers/PrivacyModeManager';
import { SettingsManager, SettingKeys } from 'manxia_core/src/main/ets/Framework/Managers/SettingsManager';

const TAG = 'PrivacyAuthDialogComponent';

export type PrivacyAuthDialogMode = 'verify' | 'setup';

@Component
export struct PrivacyAuthDialogComponent {
  // 从父组件接收的属性
  @Prop themeState: ThemeAwareState = new ThemeAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @Prop @Watch('onLoadSignalChanged') loadSignal: number = 0;
  @Prop initialMode: PrivacyAuthDialogMode = 'verify';

  // 回调函数
  onAuthSuccess?: () => void;

  // 对话框内部状态（从 MainMenuPage 迁移）
  @State showPrivacyAuthDialog: boolean = false;
  @State privacyAuthDialogVisible: boolean = false;
  @State privacyAuthDialogMode: PrivacyAuthDialogMode = 'verify';
  @State privacyAuthPasswordInput: string = '';
  @State privacyAuthPasswordConfirmInput: string = '';
  @State privacyAuthShowPassword: boolean = false;
  @State privacyAuthErrorMessage: string = '';
  @State privacyAuthSubmitting: boolean = false;

  // 私有成员
  private privacyAuthDialogAnimationToken: number = 0;
  private readonly PRIVACY_AUTH_DIALOG_ANIMATION_DURATION: number = 220;
  private privacyModeManager: PrivacyModeManager = PrivacyModeManager.getInstance();
  private settingsManager: SettingsManager = SettingsManager.getInstance();

  // ==================== 生命周期 ====================

  onLoadSignalChanged(): void {
    if (this.loadSignal > 0) {
      this.openPrivacyAuthDialog(this.initialMode);
    }
  }

  // ==================== 对话框控制 ====================

  private shouldSkipPrivacyBiometricAuth(): boolean {
    return this.settingsManager.getBoolean(SettingKeys.PRIVACY_LIBRARY_SKIP_BIOMETRIC_AUTH, false);
  }

  private resetPrivacyAuthDialogInputs(): void {
    this.privacyAuthPasswordInput = '';
    this.privacyAuthPasswordConfirmInput = '';
    this.privacyAuthShowPassword = false;
    this.privacyAuthErrorMessage = '';
  }

  private openPrivacyAuthDialog(mode: PrivacyAuthDialogMode): void {
    this.privacyAuthDialogAnimationToken += 1;
    const token: number = this.privacyAuthDialogAnimationToken;
    this.privacyAuthDialogMode = mode;
    this.privacyAuthSubmitting = false;
    this.resetPrivacyAuthDialogInputs();
    this.showPrivacyAuthDialog = true;
    this.privacyAuthDialogVisible = false;
    setTimeout(() => {
      if (this.privacyAuthDialogAnimationToken !== token || !this.showPrivacyAuthDialog) {
        return;
      }
      this.privacyAuthDialogVisible = true;
    }, 0);
  }

  private closePrivacyAuthDialog(forceClose: boolean = false): void {
    if (this.privacyAuthSubmitting && !forceClose) {
      return;
    }
    if (!this.showPrivacyAuthDialog) {
      return;
    }
    this.privacyAuthDialogAnimationToken += 1;
    const token: number = this.privacyAuthDialogAnimationToken;
    this.privacyAuthDialogVisible = false;
    setTimeout(() => {
      if (this.privacyAuthDialogAnimationToken !== token) {
        return;
      }
      this.showPrivacyAuthDialog = false;
      this.privacyAuthSubmitting = false;
      this.resetPrivacyAuthDialogInputs();
    }, this.PRIVACY_AUTH_DIALOG_ANIMATION_DURATION);
  }

  private validatePrivacyAuthInput(): boolean {
    const trimmedPassword: string = this.privacyAuthPasswordInput.trim();
    if (trimmedPassword.length === 0) {
      this.privacyAuthErrorMessage = '请输入密码';
      return false;
    }
    if (this.privacyAuthDialogMode === 'setup') {
      if (trimmedPassword.length < 6) {
        this.privacyAuthErrorMessage = '密码长度至少为6位';
        return false;
      }
      if (this.privacyAuthPasswordInput !== this.privacyAuthPasswordConfirmInput) {
        this.privacyAuthErrorMessage = '两次输入的密码不一致';
        return false;
      }
    }
    this.privacyAuthErrorMessage = '';
    return true;
  }

  private async submitPrivacyAuthDialog(): Promise<void> {
    if (this.privacyAuthSubmitting) {
      return;
    }
    if (!this.validatePrivacyAuthInput()) {
      return;
    }
    this.privacyAuthSubmitting = true;
    try {
      const password: string = this.privacyAuthPasswordInput;
      if (this.privacyAuthDialogMode === 'setup') {
        await this.privacyModeManager.setPrivacyPassword(password);
        const setupSuccess: boolean = await this.privacyModeManager.enterPrivacyModeWithPassword(password);
        if (!setupSuccess) {
          this.privacyAuthErrorMessage = '初始化成功，但进入隐私书库失败，请重试';
          return;
        }
        this.closePrivacyAuthDialog(true);
        this.getUIContext().getPromptAction().showToast({ message: '隐私密码已初始化，已进入隐私书库' });
        this.onAuthSuccess?.();
        return;
      }

      if (!this.privacyModeManager.hasPrivacyPassword()) {
        this.privacyAuthDialogMode = 'setup';
        this.privacyAuthPasswordInput = '';
        this.privacyAuthPasswordConfirmInput = '';
        this.privacyAuthErrorMessage = '未检测到隐私密码，请先初始化';
        return;
      }

      const success: boolean = await this.privacyModeManager.enterPrivacyModeWithPassword(password);
      if (success) {
        this.closePrivacyAuthDialog(true);
        this.getUIContext().getPromptAction().showToast({ message: '已进入隐私书库' });
        this.onAuthSuccess?.();
      } else {
        this.privacyAuthErrorMessage = '密码错误，请重试';
      }
    } catch (error) {
      logger.error(TAG, `隐私密码验证流程异常: ${String(error)}`);
      this.privacyAuthErrorMessage = '验证失败，请稍后重试';
    } finally {
      this.privacyAuthSubmitting = false;
    }
  }

  private getPrivacyAuthDialogTitle(): string {
    return this.privacyAuthDialogMode === 'setup' ? '初始化隐私密码' : '验证身份';
  }

  private getPrivacyAuthDialogDescription(): string {
    const skipBiometricAuth: boolean = this.shouldSkipPrivacyBiometricAuth();
    if (this.privacyAuthDialogMode === 'setup') {
      if (skipBiometricAuth) {
        return '已关闭指纹识别，请先设置隐私密码用于进入隐私书库。';
      }
      return '当前设备无法通过指纹直接验证，请先设置隐私密码用于后续进入隐私书库。';
    }
    if (skipBiometricAuth) {
      return '已关闭指纹识别，请输入隐私密码继续。';
    }
    return '指纹验证不可用或未通过，请输入隐私密码继续。';
  }

  private getPrivacyAuthConfirmButtonText(): string {
    if (this.privacyAuthSubmitting) {
      return this.privacyAuthDialogMode === 'setup' ? '初始化中...' : '验证中...';
    }
    return this.privacyAuthDialogMode === 'setup' ? '设置并进入' : '验证进入';
  }

  // ==================== UI ====================

  @Builder
  buildPrivacyAuthDialog() {
    Stack() {
      SourceDialogScaffold({
        themeState: this.themeState,
        closeOnMaskTap: !this.privacyAuthSubmitting,
        dialogWidth: '90%',
        maxWidth: 560,
        maxHeight: '86%',
        contentPadding: 24,
        dialogRadius: DialogSurfaceStyleHelper.getPopupCardRadius(),
        shadowOffsetY: 8,
        zIndexValue: 9400,
        onMaskTap: () => {
          this.closePrivacyAuthDialog();
        }
      }) {
        Column({ space: 20 }) {
          Text(this.getPrivacyAuthDialogTitle())
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .width('100%')
            .textAlign(TextAlign.Start)

          Text(this.getPrivacyAuthDialogDescription())
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .lineHeight(20)
            .width('100%')
            .textAlign(TextAlign.Start)

          Column({ space: 12 }) {
            TextInput({ placeholder: '请输入隐私密码', text: this.privacyAuthPasswordInput })
              .type(this.privacyAuthShowPassword ? InputType.Normal : InputType.Password)
              .width('100%')
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
              .borderRadius(8)
              .onChange((value: string) => {
                this.privacyAuthPasswordInput = value;
                if (this.privacyAuthErrorMessage.length > 0) {
                  this.privacyAuthErrorMessage = '';
                }
              })
              .onSubmit(() => {
                void this.submitPrivacyAuthDialog();
              })

            if (this.privacyAuthDialogMode === 'setup') {
              TextInput({ placeholder: '请再次输入隐私密码', text: this.privacyAuthPasswordConfirmInput })
                .type(this.privacyAuthShowPassword ? InputType.Normal : InputType.Password)
                .width('100%')
                .fontFamily(this.appFontFamily)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
                .borderRadius(8)
                .onChange((value: string) => {
                  this.privacyAuthPasswordConfirmInput = value;
                  if (this.privacyAuthErrorMessage.length > 0) {
                    this.privacyAuthErrorMessage = '';
                  }
                })
                .onSubmit(() => {
                  void this.submitPrivacyAuthDialog();
                })
            }

            Row({ space: 8 }) {
              Button() {
                Row({ space: 6 }) {
                  SymbolGlyph($r(this.privacyAuthShowPassword ? 'sys.symbol.eye_slash' : 'sys.symbol.eye'))
                    .fontSize(14)
                    .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])

                  Text(this.privacyAuthShowPassword ? '隐藏密码' : '显示密码')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                }
              }
              .height(24)
              .padding({ left: 8, right: 8 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
              .borderRadius(8)
              .onClick(() => {
                this.privacyAuthShowPassword = !this.privacyAuthShowPassword;
              })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')

          if (this.privacyAuthErrorMessage.length > 0) {
            Text(this.privacyAuthErrorMessage)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
              .width('100%')
              .textAlign(TextAlign.Start)
          }

          Row({ space: 12 }) {
            Button(this.privacyAuthDialogMode === 'setup' ? '暂不设置' : '取消')
              .layoutWeight(1)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
              .enabled(!this.privacyAuthSubmitting)
              .onClick(() => {
                this.closePrivacyAuthDialog();
              })

            Button(this.getPrivacyAuthConfirmButtonText())
              .layoutWeight(1)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(Color.White)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .enabled(!this.privacyAuthSubmitting)
              .opacity(this.privacyAuthSubmitting ? 0.5 : 1.0)
              .onClick(() => {
                void this.submitPrivacyAuthDialog();
              })
          }
          .width('100%')
        }
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .opacity(this.privacyAuthDialogVisible ? 1 : 0)
    .scale({
      x: this.privacyAuthDialogVisible ? 1 : 0.96,
      y: this.privacyAuthDialogVisible ? 1 : 0.96
    })
    .animation({ duration: this.PRIVACY_AUTH_DIALOG_ANIMATION_DURATION, curve: Curve.EaseOut })
    .zIndex(9400)
  }

  build() {
    if (this.showPrivacyAuthDialog) {
      this.buildPrivacyAuthDialog()
    } else {
      Column()
    }
  }
}
