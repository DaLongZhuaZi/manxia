/**
 * 浠ｇ悊閰嶇疆瀵硅瘽妗?
 * 用于配置HTTP/HTTPS代理
 */

import { ThemeAwareHelper } from '../../Framework/Components/ThemeAware';
import { ThemeType } from '../../Framework/Managers/ThemeManager';
import { ProxyConfig, DEFAULT_PROXY_CONFIG } from '../../Framework/Network/ProxyManager';

@ComponentV2
export struct ProxyConfigDialog {
  @Param @Require currentTheme: ThemeType;
  @Param @Require initialConfig: ProxyConfig;
  @Param @Require onSave: (config: ProxyConfig) => void;
  @Param @Require onCancel: () => void;

  @Local config: ProxyConfig = DEFAULT_PROXY_CONFIG;
  @Local httpHostInput: string = '';
  @Local httpPortInput: string = '';
  @Local httpsHostInput: string = '';
  @Local httpsPortInput: string = '';

  aboutToAppear(): void {
    // 鎵嬪姩澶嶅埗閰嶇疆锛圓rkTS 涓嶆敮鎸佸璞″睍寮€鎿嶄綔绗︼級
    this.config = {
      enabled: this.initialConfig.enabled,
      httpEnabled: this.initialConfig.httpEnabled,
      httpHost: this.initialConfig.httpHost,
      httpPort: this.initialConfig.httpPort,
      httpsEnabled: this.initialConfig.httpsEnabled,
      httpsHost: this.initialConfig.httpsHost,
      httpsPort: this.initialConfig.httpsPort
    };
    this.httpHostInput = this.config.httpHost;
    this.httpPortInput = this.config.httpPort.toString();
    this.httpsHostInput = this.config.httpsHost || this.config.httpHost;
    this.httpsPortInput = (this.config.httpsPort || this.config.httpPort).toString();
  }

  build() {
    Column() {
      Column() {
        // 标题
        Row() {
          SymbolGlyph($r('sys.symbol.satellite'))
            .fontSize(24)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.currentTheme)])
          
          Text('网络代理设置')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
            .margin({ left: 8 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ bottom: 16 })

        // 鍙粴鍔ㄥ唴瀹瑰尯鍩?
        Scroll() {
          Column() {
            // 鍚敤寮€鍏?
            Row() {
              Text('启用代理')
                .fontSize(16)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
              
              Blank()
              
              Toggle({ type: ToggleType.Switch, isOn: this.config.enabled })
                .onChange((isOn: boolean) => {
                  this.config.enabled = isOn;
                })
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })

            Divider()
              .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))
              .margin({ top: 12, bottom: 12 })

            // HTTP代理配置
            Column({ space: 8 }) {
              Row() {
                Toggle({ type: ToggleType.Checkbox, isOn: this.config.httpEnabled })
                  .onChange((isOn: boolean) => {
                    this.config.httpEnabled = isOn;
                  })
                
                Text('HTTP代理')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
                  .margin({ left: 8 })
              }
              .width('100%')

              Row({ space: 8 }) {
                TextInput({ placeholder: '代理地址', text: this.httpHostInput })
                  .layoutWeight(2)
                  .height(40)
                  .borderRadius(8)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
                  .onChange((value: string) => {
                    this.httpHostInput = value;
                    this.config.httpHost = value;
                  })
                  .enabled(this.config.httpEnabled)

                TextInput({ placeholder: '端口', text: this.httpPortInput })
                  .layoutWeight(1)
                  .height(40)
                  .borderRadius(8)
                  .type(InputType.Number)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
                  .onChange((value: string) => {
                    this.httpPortInput = value;
                    const port = parseInt(value);
                    if (!isNaN(port) && port > 0 && port <= 65535) {
                      this.config.httpPort = port;
                    }
                  })
                  .enabled(this.config.httpEnabled)
              }
              .width('100%')
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })

            Divider()
              .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))
              .margin({ top: 12, bottom: 12 })

            // HTTPS代理配置
            Column({ space: 8 }) {
              Row() {
                Toggle({ type: ToggleType.Checkbox, isOn: this.config.httpsEnabled })
                  .onChange((isOn: boolean) => {
                    this.config.httpsEnabled = isOn;
                  })
                
                Text('HTTPS代理')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
                  .margin({ left: 8 })
                
                Text('(鍙€?')
                  .fontSize(12)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.currentTheme))
                  .margin({ left: 4 })
              }
              .width('100%')

              Row({ space: 8 }) {
                TextInput({ placeholder: '代理地址', text: this.httpsHostInput })
                  .layoutWeight(2)
                  .height(40)
                  .borderRadius(8)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
                  .onChange((value: string) => {
                    this.httpsHostInput = value;
                    this.config.httpsHost = value;
                  })
                  .enabled(this.config.httpsEnabled)

                TextInput({ placeholder: '端口', text: this.httpsPortInput })
                  .layoutWeight(1)
                  .height(40)
                  .borderRadius(8)
                  .type(InputType.Number)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
                  .onChange((value: string) => {
                    this.httpsPortInput = value;
                    const port = parseInt(value);
                    if (!isNaN(port) && port > 0 && port <= 65535) {
                      this.config.httpsPort = port;
                    }
                  })
                  .enabled(this.config.httpsEnabled)
              }
              .width('100%')
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })

            // 提示信息
            Text('提示：代理将应用于图源的网络请求')
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.currentTheme))
              .margin({ top: 12 })
          }
          .width('100%')
        }
        .width('100%')
        .constraintSize({ maxHeight: '50%' })
        .scrollBar(BarState.Auto)

        // 按钮
        Row({ space: 16 }) {
          Button('取消')
            .fontSize(14)
            .height(34)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.currentTheme))
            .borderRadius(8)
            .layoutWeight(1)
            .onClick(() => {
              this.onCancel();
            })

          Button('保存')
            .fontSize(14)
            .height(34)
            .fontColor('#FFFFFF')
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
            .borderRadius(8)
            .layoutWeight(1)
            .onClick(() => {
              this.onSave(this.config);
            })
        }
        .width('100%')
        .margin({ top: 20 })
      }
      .width('90%')
      .constraintSize({ maxWidth: 560, maxHeight: '86%' })
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.currentTheme))
      .borderRadius(14)
      .border({
        width: 1,
        color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.currentTheme)
      })
      .shadow({
        radius: 16,
        color: ThemeAwareHelper.getTestManagementThemedColor('shadow_black', this.currentTheme),
        offsetY: 6
      })
      .padding(20)
      .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
        .combine(TransitionEffect.scale({ x: 0.95, y: 0.95 }).animation({ duration: 200, curve: Curve.EaseOut })))
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .justifyContent(FlexAlign.Center)
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
  }
}
