import { logger } from '../../Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from './ThemeAware';
import { FontAwareHelper, FontAwareState } from './FontAware';
import { DialogSurfaceStyleHelper } from './DialogSurfaceStyleHelper';
import { UIContext, curves } from '@kit.ArkUI';

const TAG = 'UniversalDialog';

export enum ButtonStyle {
  PRIMARY,   // 主要按钮 (例如：确认, 保存)
  SECONDARY, // 次要按钮 (例如：取消, 关闭)
  DESTRUCTIVE, // 破坏性操作按钮 (例如：删除)
  CUSTOM
}

export interface DialogButton {
  text: string;
  style: ButtonStyle;
  action: () => void;
}

export interface UniversalDialogOptions {
  title: string;
  message?: string;
  customBuilder?: () => void; // 用于构建复杂内容的自定义构建器
  buttons: DialogButton[];
  themeState: ThemeAwareState;
}

// 明确的类型接口：系统 ActionMenu 的按钮与选项
interface ActionMenuButtonDef {
  text: string;
  color: Resource;
}

interface ActionMenuOptionsDef {
  title: string;
  buttons: [
    ActionMenuButtonDef,
    ActionMenuButtonDef?,
    ActionMenuButtonDef?,
    ActionMenuButtonDef?,
    ActionMenuButtonDef?,
    ActionMenuButtonDef?
  ];
  // 可选窗口属性（若系统版本支持）
  isModal?: boolean;
  showInSubWindow?: boolean;
}

// 动画参数类型（与系统UIContext.animateTo兼容的最小子集）
interface AnimateParam {
  duration: number;
  curve: Curve;
}

// 使用声明式组件渲染自定义内容，避免在 build 中调用普通函数
@Component
struct CustomContentRenderer {
  @BuilderParam content: () => void;

  build() {
    this.content();
  }
}

@CustomDialog
struct UniversalDialog {
  controller: CustomDialogController;
  @Prop options: UniversalDialogOptions;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private uiContext: UIContext | undefined = undefined;
  @State private animOpacity: number = 0.0;
  @State private animScale: number = 0.96;

  private handleButtonClick(button: DialogButton): void {
    let hasError: boolean = false;
    let errorMessage: string = '';
    try {
      button.action();
    } catch (err) {
      const typedErr: Error = err as Error;
      const msg: string = typedErr && typedErr.message ? typedErr.message : String(err);
      errorMessage = msg;
      hasError = true;
    } finally {
      this.controller.close();
    }
    if (hasError) {
      logger.error(TAG, `Dialog button action failed: ${errorMessage}`);
    }
  }

  private getButtonBackgroundColor(style: ButtonStyle): Resource {
    switch (style) {
      case ButtonStyle.PRIMARY:
        return ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.options.themeState.currentTheme);
      case ButtonStyle.DESTRUCTIVE:
        return ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.options.themeState.currentTheme);
      case ButtonStyle.SECONDARY:
      default:
        return ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.options.themeState.currentTheme);
    }
  }


  build() {
    Column({ space: 16 }) {
      // 1. 标题
      Text(this.options.title)
        .fontSize(18)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.options.themeState.currentTheme))
        .width('100%')
        .textAlign(TextAlign.Start)

      // 2. 消息文本或自定义内容
      if (this.options.customBuilder) {
        // 使用声明式组件包装自定义内容，以符合 ArkTS UI 语法
        CustomContentRenderer({ content: this.options.customBuilder })
      }
      if (!this.options.customBuilder && this.options.message) {
        Text(this.options.message)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.options.themeState.currentTheme))
          .width('100%')
          .textAlign(TextAlign.Start)
      }

      // 3. 按钮行
      Row({ space: 12 }) {
        ForEach(this.options.buttons, (button: DialogButton) => {
          Button(button.text)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.options.themeState.currentTheme))
            .backgroundColor(this.getButtonBackgroundColor(button.style))
            .borderRadius(8)
            .height(40)
            .layoutWeight(1)
            .onClick(() => this.handleButtonClick(button))
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

    }
    .width('90%')
    .padding(20)
    .opacity(this.animOpacity)
    .scale({ x: this.animScale, y: this.animScale })
    .backgroundBlurStyle(
      DialogSurfaceStyleHelper.getPopupCardBlurStyle(),
      DialogSurfaceStyleHelper.getPopupCardBlurOptions()
    )
    .backgroundColor(DialogSurfaceStyleHelper.getPopupCardBackground(this.options.themeState))
    .border({ width: 1, color: DialogSurfaceStyleHelper.getPopupCardBorderColor(this.options.themeState), radius: 12 })
    .shadow({
      radius: 18,
      color: DialogSurfaceStyleHelper.getPopupCardShadowColor(this.options.themeState),
      offsetY: 8
    })
  }

  aboutToAppear(): void {
    logger.lifecycle(TAG, 'UniversalDialog.aboutToAppear');
    this.uiContext = this.getUIContext();
    const ctx = this.uiContext;
    if (!ctx) {
      logger.warn(TAG, '获取UIContext失败，跳过入场动画');
      this.animOpacity = 1.0;
      this.animScale = 1.0;
      return;
    }
    setTimeout(() => {
      const animateOptions = { duration: 220, curve: Curve.EaseOut } as AnimateParam;
      ctx.animateTo(animateOptions, () => {
        this.animOpacity = 1.0;
        this.animScale = 1.0;
      });
    }, 0);
  }
}

export class UniversalDialogManager {
  private static currentController: CustomDialogController | undefined = undefined;
  public static show(options: UniversalDialogOptions): void {
    // 如果已有正在显示的对话框，先关闭
    if (UniversalDialogManager.currentController) {
      try {
        UniversalDialogManager.currentController.close();
      } catch (err) {
        const e: Error = err as Error;
        logger.warn(TAG, `关闭旧对话框失败: ${e.message}`);
      }
      UniversalDialogManager.currentController = undefined;
    }

    const dialogController: CustomDialogController = new CustomDialogController({
      builder: () => { UniversalDialog({ options: options }); },
      alignment: DialogAlignment.Center,
      autoCancel: false,
      customStyle: true
    });
    // 持久化引用，避免被回收
    UniversalDialogManager.currentController = dialogController;
    logger.info(TAG, 'UniversalDialogController 创建完成，准备打开对话框');
    // 延迟到下一事件循环，确保与当前页面 UI 树绑定后再打开
    setTimeout((): void => {
      dialogController.open();
      logger.info(TAG, 'UniversalDialogController.open() 已调用');
    }, 0);
  }

  /**
   * 使用页面 UIContext 的 PromptAction 显示系统 ActionMenu 作为选择对话框。
   * 该实现确保挂载在有效的页面上下文中，规避自定义弹窗在未完成渲染批次时的挂载失败。
   */
  public static showWithContext(uiContext: UIContext, options: UniversalDialogOptions): void {
    try {
      const prompt = uiContext.getPromptAction();
      if (!prompt) {
        logger.error(TAG, 'PromptAction 获取失败，无法显示系统选择对话框');
        return;
      }
      if (!options.buttons || options.buttons.length === 0) {
        logger.warn(TAG, '系统选择对话框未提供按钮，取消显示');
        return;
      }

      const mapColor = (btn: DialogButton): Resource => {
        switch (btn.style) {
          case ButtonStyle.PRIMARY:
            return ThemeAwareHelper.getTestManagementThemedColor('accent_green', options.themeState.currentTheme);
          case ButtonStyle.DESTRUCTIVE:
            return ThemeAwareHelper.getTestManagementThemedColor('button_danger', options.themeState.currentTheme);
          case ButtonStyle.SECONDARY:
          default:
            return ThemeAwareHelper.getTestManagementThemedColor('button_inactive', options.themeState.currentTheme);
        }
      };

      const b1: ActionMenuButtonDef = { text: options.buttons[0].text, color: mapColor(options.buttons[0]) };
      const b2: ActionMenuButtonDef | undefined = options.buttons.length > 1 ? { text: options.buttons[1].text, color: mapColor(options.buttons[1]) } : undefined;
      const b3: ActionMenuButtonDef | undefined = options.buttons.length > 2 ? { text: options.buttons[2].text, color: mapColor(options.buttons[2]) } : undefined;
      const b4: ActionMenuButtonDef | undefined = options.buttons.length > 3 ? { text: options.buttons[3].text, color: mapColor(options.buttons[3]) } : undefined;
      const b5: ActionMenuButtonDef | undefined = options.buttons.length > 4 ? { text: options.buttons[4].text, color: mapColor(options.buttons[4]) } : undefined;
      const b6: ActionMenuButtonDef | undefined = options.buttons.length > 5 ? { text: options.buttons[5].text, color: mapColor(options.buttons[5]) } : undefined;

      let actionMenuOptions: ActionMenuOptionsDef;
      const btnCount: number = options.buttons.length;
      if (btnCount === 1) {
        actionMenuOptions = { title: options.title, buttons: [b1], isModal: true };
      } else if (btnCount === 2 && b2) {
        actionMenuOptions = { title: options.title, buttons: [b1, b2], isModal: true };
      } else if (btnCount === 3 && b2 && b3) {
        actionMenuOptions = { title: options.title, buttons: [b1, b2, b3], isModal: true };
      } else if (btnCount === 4 && b2 && b3 && b4) {
        actionMenuOptions = { title: options.title, buttons: [b1, b2, b3, b4], isModal: true };
      } else if (btnCount === 5 && b2 && b3 && b4 && b5) {
        actionMenuOptions = { title: options.title, buttons: [b1, b2, b3, b4, b5], isModal: true };
      } else if (btnCount >= 6 && b2 && b3 && b4 && b5 && b6) {
        actionMenuOptions = { title: options.title, buttons: [b1, b2, b3, b4, b5, b6], isModal: true };
      } else {
        // 按钮构造异常（存在 undefined），防御退出
        logger.error(TAG, 'ActionMenu 按钮构造异常，取消显示');
        return;
      }

      prompt.showActionMenu(actionMenuOptions, (err, data): void => {
        if (err) {
          logger.error(TAG, '系统选择对话框显示失败', String(err));
          return;
        }
        const idx = data.index;
        if (idx < 0 || idx >= options.buttons.length) {
          logger.warn(TAG, `无效的按钮索引: ${String(idx)}`);
          return;
        }
        const chosen = options.buttons[idx];
        try {
          chosen.action();
        } catch (actionError) {
          logger.error(TAG, `选择操作执行失败: ${String(actionError instanceof Error ? actionError.message : actionError)}`);
        }
      });
      logger.info(TAG, 'showWithContext 已调用（系统 ActionMenu）');
    } catch (error) {
      const e: Error = error as Error;
      logger.error(TAG, 'showWithContext 调用失败', e.message);
    }
  }
}
