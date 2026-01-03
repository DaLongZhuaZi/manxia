import { promptAction } from '@kit.ArkUI';
import { logger } from '../utils/Logger';

const TAG = 'PrivacyAuthDialog';

@CustomDialog
export struct PrivacyAuthDialog {
  controller: CustomDialogController;
  onConfirm?: (password: string) => void;
  onCancel?: () => void;
  
  @State private password: string = '';
  @State private showPassword: boolean = false;

  build() {
    Column({ space: 20 }) {
      // 标题
      Text('验证身份')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Center)

      // 说明文字
      Text('请输入隐私密码以进入隐私书库')
        .fontSize(14)
        .fontColor('#666666')
        .width('100%')
        .textAlign(TextAlign.Center)

      // 密码输入框
      Row({ space: 8 }) {
        TextInput({ placeholder: '请输入密码' })
          .type(this.showPassword ? InputType.Normal : InputType.Password)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.password = value;
          })
          .onSubmit(() => {
            this.handleConfirm();
          })

        // 显示/隐藏密码按钮
        Button() {
          Image($r(this.showPassword ? 'sys.symbol.eye_slash' : 'sys.symbol.eye'))
            .width(20)
            .height(20)
            .fillColor('#666666')
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showPassword = !this.showPassword;
        })
      }
      .width('100%')

      // 按钮组
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .backgroundColor('#F0F0F0')
          .fontColor('#333333')
          .onClick(() => {
            this.handleCancel();
          })

        Button('确认')
          .layoutWeight(1)
          .backgroundColor('#007DFF')
          .fontColor(Color.White)
          .onClick(() => {
            this.handleConfirm();
          })
      }
      .width('100%')
    }
    .padding(24)
    .backgroundColor(Color.White)
    .borderRadius(16)
  }

  private handleConfirm(): void {
    if (!this.password || this.password.trim().length === 0) {
      promptAction.showToast({
        message: '请输入密码',
        duration: 2000
      });
      return;
    }

    if (this.onConfirm) {
      this.onConfirm(this.password);
    }
    this.controller.close();
  }

  private handleCancel(): void {
    if (this.onCancel) {
      this.onCancel();
    }
    this.controller.close();
  }
}

@CustomDialog
export struct SetPrivacyPasswordDialog {
  controller: CustomDialogController;
  onConfirm?: (password: string) => void;
  onCancel?: () => void;
  
  @State private password: string = '';
  @State private confirmPassword: string = '';
  @State private showPassword: boolean = false;

  build() {
    Column({ space: 20 }) {
      // 标题
      Text('设置隐私密码')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Center)

      // 说明文字
      Text('设置密码后，可在生物识别失败时使用密码验证')
        .fontSize(14)
        .fontColor('#666666')
        .width('100%')
        .textAlign(TextAlign.Center)

      // 密码输入框
      Column({ space: 12 }) {
        TextInput({ placeholder: '请输入密码（至少6位）' })
          .type(this.showPassword ? InputType.Normal : InputType.Password)
          .onChange((value: string) => {
            this.password = value;
          })

        TextInput({ placeholder: '请再次输入密码' })
          .type(this.showPassword ? InputType.Normal : InputType.Password)
          .onChange((value: string) => {
            this.confirmPassword = value;
          })
          .onSubmit(() => {
            this.handleConfirm();
          })

        // 显示/隐藏密码
        Row({ space: 8 }) {
          Checkbox()
            .select(this.showPassword)
            .onChange((value: boolean) => {
              this.showPassword = value;
            })
          Text('显示密码')
            .fontSize(14)
            .fontColor('#666666')
        }
        .width('100%')
      }
      .width('100%')

      // 按钮组
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .backgroundColor('#F0F0F0')
          .fontColor('#333333')
          .onClick(() => {
            this.handleCancel();
          })

        Button('确认')
          .layoutWeight(1)
          .backgroundColor('#007DFF')
          .fontColor(Color.White)
          .onClick(() => {
            this.handleConfirm();
          })
      }
      .width('100%')
    }
    .padding(24)
    .backgroundColor(Color.White)
    .borderRadius(16)
  }

  private handleConfirm(): void {
    if (!this.password || this.password.trim().length === 0) {
      promptAction.showToast({
        message: '请输入密码',
        duration: 2000
      });
      return;
    }

    if (this.password.length < 6) {
      promptAction.showToast({
        message: '密码长度至少为6位',
        duration: 2000
      });
      return;
    }

    if (this.password !== this.confirmPassword) {
      promptAction.showToast({
        message: '两次输入的密码不一致',
        duration: 2000
      });
      return;
    }

    if (this.onConfirm) {
      this.onConfirm(this.password);
    }
    this.controller.close();
  }

  private handleCancel(): void {
    if (this.onCancel) {
      this.onCancel();
    }
    this.controller.close();
  }
}
