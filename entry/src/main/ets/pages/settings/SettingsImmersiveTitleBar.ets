import { ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { SettingsImmersiveTitleActionItem, SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';
import { ngfNavigationShellFacade } from '../../Framework/NGF/uiShell/index';

interface SettingsImmersiveThemeState {
  currentTheme: ThemeType;
}

@Component
export struct SettingsImmersiveTitleActionButton {
  @Prop themeState: SettingsImmersiveThemeState;
  @Prop glyph: Resource;
  @Prop buttonEnabled: boolean = true;
  @Prop accessibilityLabel: string = '';
  @Prop actionId: string = '';
  tapHandler: () => void = () => {};
  @State private isPressed: boolean = false;

  private getCurrentTheme(): ThemeType {
    return this.themeState.currentTheme;
  }

  private updatePressedState(event: TouchEvent): void {
    if (!this.buttonEnabled) {
      this.isPressed = false;
      return;
    }

    if (event.type === TouchType.Down) {
      this.isPressed = true;
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.isPressed = false;
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(SettingsPageTitleBarManager.getButtonFillColor(this.getCurrentTheme()))
          .borderRadius(999)

        Column()
          .width('100%')
          .height('100%')
          .linearGradient(SettingsPageTitleBarManager.getButtonGlassTintGradient(this.getCurrentTheme()))
          .borderRadius(999)

        Column()
          .width('100%')
          .height('100%')
          .linearGradient(SettingsPageTitleBarManager.getButtonDepthGradient(this.getCurrentTheme()))
          .borderRadius(999)

        Column()
          .width('100%')
          .height('100%')
          .linearGradient(SettingsPageTitleBarManager.getButtonHighlightGradient(this.getCurrentTheme()))
          .borderRadius(999)
          .opacity(this.isPressed ? 0.55 : 0.78)

        Column()
          .width('58%')
          .height('58%')
          .position({ x: 4, y: 3 })
          .linearGradient(SettingsPageTitleBarManager.getButtonSpecularGradient(this.getCurrentTheme()))
          .borderRadius(999)
          .opacity(this.isPressed ? 0.42 : 0.78)

        Column()
          .width('78%')
          .height('30%')
          .position({ x: 4, y: 25 })
          .linearGradient(SettingsPageTitleBarManager.getButtonBottomShadeGradient(this.getCurrentTheme()))
          .borderRadius(999)
          .opacity(this.isPressed ? 0.22 : 0.44)

        Column()
          .width('100%')
          .height('100%')
          .border({
            width: 1,
            color: SettingsPageTitleBarManager.getButtonBorderColor(this.getCurrentTheme())
          })
          .borderRadius(999)

        Column()
          .width('100%')
          .height('100%')
          .border({
            width: 1,
            color: SettingsPageTitleBarManager.getButtonInnerBorderColor(this.getCurrentTheme())
          })
          .borderRadius(999)
          .opacity(this.isPressed ? 0.34 : 0.56)

        SymbolGlyph(this.glyph)
          .fontSize(SettingsPageTitleBarManager.BUTTON_ICON_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor([SettingsPageTitleBarManager.getButtonIconColor(this.getCurrentTheme())])
          .opacity(this.isPressed ? 0.92 : 1)
          .translate({ y: this.isPressed ? 0.8 : -0.2 })

        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(SettingsPageTitleBarManager.getButtonPressedOverlayColor(this.getCurrentTheme()))
          .borderRadius(999)
          .opacity(this.isPressed ? 1 : 0)
      }
      .width('100%')
      .height('100%')
      .borderRadius(999)
      .clip(true)
    }
    .width(SettingsPageTitleBarManager.BUTTON_SIZE)
    .height(SettingsPageTitleBarManager.BUTTON_SIZE)
    .borderRadius(999)
    .id(this.actionId)
    .accessibilityText(this.accessibilityLabel)
    .opacity(this.buttonEnabled ? 1 : 0.42)
    .shadow({
      radius: SettingsPageTitleBarManager.getButtonShadowRadius(this.isPressed),
      color: SettingsPageTitleBarManager.getButtonShadowColor(this.getCurrentTheme(), this.isPressed),
      offsetX: 0,
      offsetY: SettingsPageTitleBarManager.getButtonShadowOffsetY(this.isPressed)
    })
    .scale({
      x: this.isPressed ? 0.965 : 1,
      y: this.isPressed ? 0.965 : 1
    })
    .translate({ y: this.isPressed ? 1 : 0 })
    .animation({ duration: 180, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      this.updatePressedState(event);
    })
    .onClick(() => {
      if (!this.buttonEnabled) {
        return;
      }
      this.isPressed = false;
      this.tapHandler();
    })
  }
}

@Component
export struct SettingsImmersiveTitleBar {
  @Prop themeState: SettingsImmersiveThemeState;
  @Prop title: string;
  @Prop appFontFamily: string = 'HarmonyOS Sans';
  @Prop contentPadding: number = 16;
  @Prop maxContentWidth: number = 1200;
  @Prop hideBackButton: boolean = false;
  @Prop maxDirectActions: number = 2;
  @Prop actions: SettingsImmersiveTitleActionItem[] = [];
  @State private showOverflowMenu: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  pathStack: NavPathStack | null = null;
  backAction: (() => boolean) | null = null;
  @BuilderParam trailing: () => void = this.emptyTrailing;

  @Builder
  private emptyTrailing() {
  }

  private getCurrentTheme(): ThemeType {
    return this.themeState.currentTheme;
  }

  private getBarHeight(): number {
    return SettingsPageTitleBarManager.getTitleBarHeight(this.statusBarHeight);
  }

  private getTopPadding(): number {
    return SettingsPageTitleBarManager.getTitleBarTopPadding(this.statusBarHeight);
  }

  private getEdgeFadeStartOffset(): number {
    return SettingsPageTitleBarManager.getEdgeFadeStartOffset(this.statusBarHeight);
  }

  private getEdgeFadeLayerHeight(): number {
    return SettingsPageTitleBarManager.getEdgeFadeLayerHeight();
  }

  private getVisibleActions(): SettingsImmersiveTitleActionItem[] {
    return this.actions.filter((action: SettingsImmersiveTitleActionItem) => action.visible !== false);
  }

  private getDirectActions(): SettingsImmersiveTitleActionItem[] {
    const visibleActions = this.getVisibleActions();
    if (visibleActions.length <= this.maxDirectActions) {
      return visibleActions;
    }
    return visibleActions.slice(0, this.maxDirectActions);
  }

  private getOverflowActions(): SettingsImmersiveTitleActionItem[] {
    const visibleActions = this.getVisibleActions();
    if (visibleActions.length <= this.maxDirectActions) {
      return [];
    }
    return visibleActions.slice(this.maxDirectActions);
  }

  private getActionRenderKey(action: SettingsImmersiveTitleActionItem): string {
    const labelPart = action.label ? action.label : '';
    const enabledPart = action.enabled === false ? 'disabled' : 'enabled';
    const visiblePart = action.visible === false ? 'hidden' : 'visible';
    return `${action.id}_${labelPart}_${enabledPart}_${visiblePart}`;
  }

  private getOverflowPopupBackgroundColor(): ResourceColor {
    return this.getCurrentTheme() === ThemeType.DARK
      ? 'rgba(24, 32, 46, 0.96)'
      : 'rgba(252, 253, 255, 0.98)';
  }

  private getOverflowPopupBorderColor(): ResourceColor {
    return this.getCurrentTheme() === ThemeType.DARK
      ? 'rgba(255, 255, 255, 0.10)'
      : 'rgba(206, 220, 240, 0.90)';
  }

  private getOverflowPopupShadowColor(): ResourceColor {
    return this.getCurrentTheme() === ThemeType.DARK
      ? 'rgba(0, 0, 0, 0.24)'
      : 'rgba(170, 188, 214, 0.18)';
  }

  private getOverflowItemHoverColor(): ResourceColor {
    return this.getCurrentTheme() === ThemeType.DARK
      ? 'rgba(255, 255, 255, 0.06)'
      : 'rgba(110, 127, 152, 0.08)';
  }

  private handleOverflowAction(action: SettingsImmersiveTitleActionItem): void {
    this.showOverflowMenu = false;
    if (action.enabled === false) {
      return;
    }
    action.onClick();
  }

  @Builder
  private buildOverflowPopup() {
    Column({ space: 4 }) {
      ForEach(this.getOverflowActions(), (action: SettingsImmersiveTitleActionItem) => {
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Row({ space: 10 }) {
            SymbolGlyph(action.symbol)
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor([SettingsPageTitleBarManager.getButtonIconColor(this.getCurrentTheme())])

            Text(action.label ? action.label : action.id)
              .layoutWeight(1)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(SettingsPageTitleBarManager.getTitleColor(this.getCurrentTheme()))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({ left: 14, right: 12 })
        }
          .width('100%')
          .height(44)
          .id(`title_action_${action.id}`)
          .enabled(action.enabled === false ? false : true)
          .opacity(action.enabled === false ? 0.42 : 1)
          .backgroundColor(Color.Transparent)
          .borderRadius(14)
          .stateStyles({
            normal: {
              .backgroundColor(Color.Transparent)
            },
            pressed: {
              .backgroundColor(this.getOverflowItemHoverColor())
            }
          })
          .onClick(() => {
            this.handleOverflowAction(action);
          })
      }, (action: SettingsImmersiveTitleActionItem) => this.getActionRenderKey(action))
    }
    .width('100%')
    .padding(6)
    .backgroundColor(this.getOverflowPopupBackgroundColor())
    .borderRadius(20)
    .border({
      width: 1,
      color: this.getOverflowPopupBorderColor()
    })
    .shadow({
      radius: 22,
      color: this.getOverflowPopupShadowColor()
    })
  }

  private tryPopStack(stack: NavPathStack | null): boolean {
    if (!stack) {
      return false;
    }

    try {
      if (stack.getAllPathName().length <= 0) {
        return false;
      }
      stack.pop();
      return true;
    } catch (_err) {
      return false;
    }
  }

  private isNgfUiShellIntegrated(): boolean {
    try {
      return AppStorage.get<boolean>('ngf_ui_shell_integrated') === true;
    } catch (_err) {
      return false;
    }
  }

  private tryPopByNgfNavigationShell(): boolean {
    if (!this.isNgfUiShellIntegrated()) {
      return false;
    }

    try {
      return ngfNavigationShellFacade.pop();
    } catch (_err) {
      return false;
    }
  }

  private goBack(): void {
    if (this.backAction) {
      try {
        if (this.backAction()) {
          return;
        }
      } catch (_err) {
      }
    }

    if (this.tryPopByNgfNavigationShell()) {
      return;
    }

    try {
      const stack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (this.tryPopStack(stack ?? null)) {
        return;
      }
    } catch (_err) {
    }

    if (this.tryPopStack(this.pathStack)) {
      return;
    }

    try {
      this.getUIContext().getRouter().back();
    } catch (_err) {
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(SettingsPageTitleBarManager.getBackdropColor(this.getCurrentTheme()))
          .backdropBlur(SettingsPageTitleBarManager.getBackdropBlurRadius(this.getCurrentTheme()))
          .hitTestBehavior(HitTestMode.Transparent)

        Column()
          .width('100%')
          .height('100%')
          .linearGradient(SettingsPageTitleBarManager.getSurfaceGradient(this.getCurrentTheme()))
          .hitTestBehavior(HitTestMode.Transparent)

        Column()
          .width('24%')
          .height('62%')
          .position({ x: 0, y: 0 })
          .linearGradient(SettingsPageTitleBarManager.getReflectionGradient(this.getCurrentTheme()))
          .opacity(SettingsPageTitleBarManager.getReflectionOpacity(this.getCurrentTheme()))
          .hitTestBehavior(HitTestMode.Transparent)
      }
      .width('100%')
      .height(this.getBarHeight())
      .hitTestBehavior(HitTestMode.Transparent)

      Column()
        .width('100%')
        .height(this.getEdgeFadeLayerHeight())
        .position({ x: 0, y: this.getEdgeFadeStartOffset() })
        .linearGradient(SettingsPageTitleBarManager.getEdgeFadeGradient(this.getCurrentTheme()))
        .hitTestBehavior(HitTestMode.Transparent)

      Column() {
        Row({ space: 12 }) {
          if (!this.hideBackButton) {
            SettingsImmersiveTitleActionButton({
              themeState: this.themeState,
              glyph: $r('sys.symbol.chevron_left'),
              accessibilityLabel: '返回',
              actionId: 'title_action_back',
              tapHandler: () => {
                this.goBack();
              }
            })
          }

          Text(this.title)
            .layoutWeight(1)
            .fontSize(SettingsPageTitleBarManager.TITLE_FONT_SIZE)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(SettingsPageTitleBarManager.getTitleColor(this.getCurrentTheme()))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Row({ space: SettingsPageTitleBarManager.ACTION_BUTTON_SPACE }) {
            ForEach(this.getDirectActions(), (action: SettingsImmersiveTitleActionItem) => {
              SettingsImmersiveTitleActionButton({
                themeState: this.themeState,
                glyph: action.symbol,
                buttonEnabled: action.enabled === false ? false : true,
                accessibilityLabel: action.label ? action.label : action.id,
                actionId: `title_action_${action.id}`,
                tapHandler: action.onClick
              })
            }, (action: SettingsImmersiveTitleActionItem) => this.getActionRenderKey(action))

            if (this.getOverflowActions().length > 0) {
              SettingsImmersiveTitleActionButton({
                themeState: this.themeState,
                glyph: $r('sys.symbol.more'),
                accessibilityLabel: '更多操作',
                tapHandler: () => {
                  this.showOverflowMenu = true;
                }
              })
                .bindPopup(this.showOverflowMenu, {
                  builder: this.buildOverflowPopup(),
                  placement: Placement.BottomRight,
                  popupColor: Color.Transparent,
                  enableArrow: false,
                  autoCancel: true,
                  width: '220vp',
                  onStateChange: (e) => {
                    if (!e.isVisible) {
                      this.showOverflowMenu = false;
                    }
                  }
                })
            }

            this.trailing()
          }
        }
        .justifyContent(FlexAlign.Start)
        .alignItems(VerticalAlign.Center)
        .width('100%')
        .height(SettingsPageTitleBarManager.TITLE_BAR_ROW_HEIGHT)
        .constraintSize({ maxWidth: this.maxContentWidth })
        .padding({
          left: this.contentPadding,
          right: this.contentPadding
        })
      }
      .width('100%')
      .height(this.getBarHeight())
      .padding({ top: this.getTopPadding() })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height(this.getBarHeight())
    .align(Alignment.TopStart)
    .position({ x: 0, y: 0 })
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
    .zIndex(10)
  }
}
