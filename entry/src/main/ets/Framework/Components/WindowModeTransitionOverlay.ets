@Component
export struct WindowModeTransitionOverlay {
  @StorageLink('window_mode_transition_overlay_visible') overlayVisible: boolean = false;
  @StorageLink('window_mode_transition_overlay_opacity') overlayOpacity: number = 0;
  @StorageLink('window_mode_transition_overlay_use_blur') overlayUseBlur: boolean = true;
  @StorageLink('window_mode_transition_overlay_prefers_dark') overlayPrefersDark: boolean = true;

  build() {
    if (this.overlayVisible) {
      Stack() {
        if (this.overlayUseBlur) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN, {
              colorMode: this.overlayPrefersDark ? ThemeColorMode.DARK : ThemeColorMode.LIGHT,
              adaptiveColor: AdaptiveColor.DEFAULT,
              scale: 1.0
            })
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        }

        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.overlayPrefersDark ? '#8A000000' : '#99F3F5F7')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }
      .width('100%')
      .height('100%')
      .opacity(this.overlayOpacity)
      .animation({ duration: 180, curve: Curve.EaseInOut })
      .zIndex(9998)
      .hitTestBehavior(HitTestMode.Block)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
  }
}
