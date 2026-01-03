/**
 * 代理配置对话框
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
    this.config = { ...this.initialConfig };
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

        // 可滚动内容区域
        Scroll() {
          Column() {
            // 启用开关
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
            .padding({ vertical: 8 })

            Divider()
              .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))
              .margin({ vertical: 12 })

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
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('input_background', this.currentTheme))
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
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('input_background', this.currentTheme))
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
            .padding({ vertical: 8 })

            Divider()
              .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))
              .margin({ vertical: 12 })

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
                
                Text('(可选)')
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
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('input_background', this.currentTheme))
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
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('input_background', this.currentTheme))
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
            .padding({ vertical: 8 })

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
            .fontSize(16)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
            .borderRadius(8)
            .layoutWeight(1)
            .onClick(() => {
              this.onCancel();
            })

          Button('保存')
            .fontSize(16)
            .fontColor('#FFFFFF')
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.currentTheme))
            .borderRadius(8)
            .layoutWeight(1)
            .onClick(() => {
              this.onSave(this.config);
            })
        }
        .width('100%')
        .margin({ top: 20 })
      }
      .width('85%')
      .constraintSize({ maxHeight: '80%' })
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.currentTheme))
      .borderRadius(16)
      .padding(20)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0, 0, 0, 0.5)')
    .justifyContent(FlexAlign.Center)
  }
}
