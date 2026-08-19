/**
 * 凭据登录对话框
 * 用于需要账号密码登录的图源
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ThemeAwareHelper, ThemeAwareState } from './ThemeAware';
import { ThemeType } from '../Managers/ThemeManager';

const TAG = 'CredentialLoginDialog';

/**
 * 登录回调接口
 */
export interface CredentialLoginCallback {
  onLogin: (username: string, password: string) => void;
  onCancel: () => void;
}

/**
 * 凭据登录对话框组件
 */
@CustomDialog
export struct CredentialLoginDialog {
  controller: CustomDialogController;
  @State username: string = '';
  @State password: string = '';
  @State showPassword: boolean = false;
  @State isLoading: boolean = false;
  @Link themeState: ThemeAwareState;
  
  // 回调函数
  onLogin?: (username: string, password: string) => void;
  onCancel?: () => void;
  
  // 配置
  title: string = '登录';
  sourceName: string = '';
  usernameLabel: string = '用户名';
  passwordLabel: string = '密码';
  usernamePlaceholder: string = '请输入用户名';
  passwordPlaceholder: string = '请输入密码';
  loginButtonText: string = '登录';
  cancelButtonText: string = '取消';

  build() {
    Column({ space: 0 }) {
      // 标题栏
      Row() {
        Text(this.title)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        // 关闭按钮
        Image($r('sys.media.ohos_ic_public_cancel'))
          .width(24)
          .height(24)
          .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .onClick(() => {
            this.handleCancel();
          })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
      
      Divider()
        .color(ThemeAwareHelper.getTestManagementThemedColor('comp_divider', this.themeState.currentTheme))
      
      // 内容区域
      Column({ space: 16 }) {
        // 图源名称提示
        if (this.sourceName) {
          Text(`请输入 ${this.sourceName} 的登录凭据`)
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')
        }
        
        // 用户名输入框
        Column({ space: 8 }) {
          Text(this.usernameLabel)
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .width('100%')
          
          TextInput({ placeholder: this.usernamePlaceholder, text: this.username })
            .width('100%')
            .height(44)
            .fontSize(15)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_primary', this.themeState.currentTheme))
            .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .borderRadius(8)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.username = value;
            })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        
        // 密码输入框
        Column({ space: 8 }) {
          Text(this.passwordLabel)
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .width('100%')
          
          Row() {
            TextInput({ 
              placeholder: this.passwordPlaceholder, 
              text: this.password 
            })
              .width('100%')
              .height(44)
              .fontSize(15)
              .type(this.showPassword ? InputType.Normal : InputType.Password)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_primary', this.themeState.currentTheme))
              .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .borderRadius(8)
              .padding({ left: 12, right: 40 })
              .onChange((value: string) => {
                this.password = value;
              })
            
            // 显示/隐藏密码按钮
            Image(this.showPassword ? $r('sys.symbol.eye') : $r('sys.symbol.eye_slash'))
              .width(20)
              .height(20)
              .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .position({ x: '100%', y: '50%' })
              .translate({ x: -32, y: '-50%' })
              .onClick(() => {
                this.showPassword = !this.showPassword;
              })
          }
          .width('100%')
          .position({ x: 0, y: 0 })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        
        // 提示信息
        Text('凭据将安全存储在本地，用于自动登录')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .width('100%')
          .margin({ top: 8 })
      }
      .padding(20)
      .width('100%')
      
      Divider()
        .color(ThemeAwareHelper.getTestManagementThemedColor('comp_divider', this.themeState.currentTheme))
      
      // 按钮区域
      Row({ space: 12 }) {
        // 取消按钮
        Button(this.cancelButtonText)
          .fontSize(15)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_primary', this.themeState.currentTheme))
          .layoutWeight(1)
          .height(44)
          .onClick(() => {
            this.handleCancel();
          })
        
        // 登录按钮
        Button(this.loginButtonText)
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .layoutWeight(1)
          .height(44)
          .enabled(!this.isLoading && this.username.trim().length > 0 && this.password.trim().length > 0)
          .opacity((!this.isLoading && this.username.trim().length > 0 && this.password.trim().length > 0) ? 1.0 : 0.5)
          .onClick(() => {
            this.handleLogin();
          })
      }
      .padding(16)
      .width('100%')
    }
    .width('85%')
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(16)
  }
  
  /**
   * 处理登录
   */
  private handleLogin(): void {
    if (this.isLoading) {
      return;
    }
    
    const username = this.username.trim();
    const password = this.password.trim();
    
    if (!username || !password) {
      logger.warn(TAG, '用户名或密码为空');
      return;
    }
    
    logger.info(TAG, `用户登录: ${username}`);
    
    // 调用回调
    if (this.onLogin) {
      this.onLogin(username, password);
    }
    
    // 关闭对话框
    this.controller.close();
  }
  
  /**
   * 处理取消
   */
  private handleCancel(): void {
    logger.info(TAG, '用户取消登录');
    
    // 调用回调
    if (this.onCancel) {
      this.onCancel();
    }
    
    // 关闭对话框
    this.controller.close();
  }
}
