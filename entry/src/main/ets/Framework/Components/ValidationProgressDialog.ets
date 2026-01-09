/**
 * 书源校验进度对话框
 * 显示实时进度、统计信息和取消按钮
 * 
 * 文件路径: entry/src/main/ets/Framework/Components/ValidationProgressDialog.ets
 */

import { ThemeAwareState, ThemeAwareHelper } from './ThemeAware';
import { AppColors } from '../Theme/AppColors';

/**
 * 校验进度信息
 */
export interface ValidationProgressInfo {
  current: number;
  total: number;
  validCount: number;
  invalidCount: number;
  currentSourceName: string;
  isComplete: boolean;
  isCancelled: boolean;
  invalidSourceIds?: string[];  // 失效的书源ID列表
}

/**
 * 校验进度对话框控制器接口
 */
export interface ValidationProgressController {
  updateProgress: (info: ValidationProgressInfo) => void;
  close: () => void;
}

@CustomDialog
export struct ValidationProgressDialog {
  controller: CustomDialogController;
  @Prop themeState: ThemeAwareState;
  @State progressInfo: ValidationProgressInfo = {
    current: 0,
    total: 0,
    validCount: 0,
    invalidCount: 0,
    currentSourceName: '',
    isComplete: false,
    isCancelled: false
  };
  
  // 取消回调
  onCancel?: () => void;
  // 进度控制器回调
  onControllerReady?: (ctrl: ValidationProgressController) => void;
  // 关闭失效书源回调
  onCloseInvalidSources?: () => void;
  
  aboutToAppear(): void {
    // 提供控制器给外部使用
    if (this.onControllerReady) {
      const ctrl: ValidationProgressController = {
        updateProgress: (info: ValidationProgressInfo) => {
          this.progressInfo = info;
          // 不再自动关闭对话框，让用户查看结果后手动关闭
        },
        close: () => {
          this.controller.close();
        }
      };
      this.onControllerReady(ctrl);
    }
  }

  build() {
    Column() {
      // 标题
      Text(this.progressInfo.isComplete ? '校验完成' : 
           this.progressInfo.isCancelled ? '校验已取消' : '书源校验中')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .margin({ bottom: 16 })
      
      // 进度条
      Progress({ value: this.progressInfo.current, total: this.progressInfo.total, type: ProgressType.Linear })
        .width('100%')
        .height(8)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
        .margin({ bottom: 12 })
      
      // 进度文本
      Text(`${this.progressInfo.current} / ${this.progressInfo.total}`)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .margin({ bottom: 8 })
      
      // 统计信息
      Row({ space: 20 }) {
        // 有效数量
        Column() {
          Text(`${this.progressInfo.validCount}`)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.success)
          Text('有效')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        
        // 失效数量
        Column() {
          Text(`${this.progressInfo.invalidCount}`)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.error)
          Text('失效')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        
        // 剩余数量
        Column() {
          Text(`${this.progressInfo.total - this.progressInfo.current}`)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Text('剩余')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
      }
      .margin({ bottom: 12 })
      
      // 当前正在校验的书源名称
      if (this.progressInfo.currentSourceName && !this.progressInfo.isComplete && !this.progressInfo.isCancelled) {
        Text(`正在校验: ${this.progressInfo.currentSourceName}`)
          .fontSize(13)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ bottom: 16 })
      }
      
      // 完成或取消状态显示
      if (this.progressInfo.isComplete) {
        Text(`校验完成！有效: ${this.progressInfo.validCount}, 失效: ${this.progressInfo.invalidCount}`)
          .fontSize(14)
          .fontColor(AppColors.success)
          .margin({ bottom: 16 })
      } else if (this.progressInfo.isCancelled) {
        Text(`已取消，完成: ${this.progressInfo.current}/${this.progressInfo.total}`)
          .fontSize(14)
          .fontColor(AppColors.error)
          .margin({ bottom: 16 })
      }
      
      // 关闭失效书源按钮（仅在校验完成且有失效书源时显示）
      if (this.progressInfo.isComplete && 
          this.progressInfo.invalidCount > 0 && 
          this.progressInfo.invalidSourceIds && 
          this.progressInfo.invalidSourceIds.length > 0) {
        Button('关闭失效书源')
          .width('100%')
          .height(44)
          .fontSize(16)
          .fontColor(AppColors.onError)
          .backgroundColor(AppColors.error)
          .borderRadius(8)
          .margin({ bottom: 8 })
          .onClick(() => {
            if (this.onCloseInvalidSources) {
              this.onCloseInvalidSources();
            }
          })
      }
      
      // 取消按钮（仅在校验进行中显示）
      if (!this.progressInfo.isComplete && !this.progressInfo.isCancelled) {
        Button('取消校验')
          .width('100%')
          .height(44)
          .fontSize(16)
          .fontColor(AppColors.onError)
          .backgroundColor(AppColors.error)
          .borderRadius(8)
          .onClick(() => {
            if (this.onCancel) {
              this.onCancel();
            }
          })
      } else {
        // 关闭按钮
        Button(this.progressInfo.isComplete && this.progressInfo.invalidCount > 0 ? '稍后处理' : '关闭')
          .width('100%')
          .height(44)
          .fontSize(16)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
          .borderRadius(8)
          .onClick(() => {
            this.controller.close();
          })
      }
    }
    .width('100%')
    .padding(24)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(16)
  }
}
