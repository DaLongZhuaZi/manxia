/**
 * WebDAV配置对话框
 * 
 * 文件路径: entry/src/main/ets/components/backup/WebDAVConfigDialog.ets
 */

import { ThemeAwareHelper } from '../../Framework/Components/ThemeAware';
import { ThemeType } from '../../Framework/Managers/ThemeManager';
import { WebDAVSettings } from '../../Models/WebDAVModels';
import { logger } from '../../Utils/Logger';
import { WebDAVTestResult } from '../../Framework/WebDAV/WebDAVClient';

const TAG = 'WebDAVConfigDialog';

@ComponentV2
export struct WebDAVConfigDialog {
  @Param @Require onConfirm: (settings: WebDAVSettings) => void;
  @Param @Require onCancel: () => void;
  @Param @Require onTest: (settings: WebDAVSettings) => Promise<WebDAVTestResult>;
  @Param @Require currentTheme: ThemeType;
  @Param settings: WebDAVSettings = {
    enabled: false,
    serverUrl: '',
    username: '',
    password: '',
    basePath: '/manxia',
    autoBackup: false,
    autoBackupInterval: 'manual',
    keepBackupCount: 5,
    lastSyncTime: 0,
    connectionStatus: 'untested',
    lastTestTime: 0,
    lastTestMessage: '',
    needCreateDir: false
  };
  @Local localSettings: WebDAVSettings = {
    enabled: false,
    serverUrl: '',
    username: '',
    password: '',
    basePath: '/manxia',
    autoBackup: false,
    autoBackupInterval: 'manual',
    keepBackupCount: 5,
    lastSyncTime: 0,
    connectionStatus: 'untested',
    lastTestTime: 0,
    lastTestMessage: '',
    needCreateDir: false
  };
  @Local isTesting: boolean = false;
  @Local testResult: string = '';
  @Local showPassword: boolean = false;
  @Local showCreateDirDialog: boolean = false;
  @Local pendingSettings: WebDAVSettings | null = null;

  aboutToAppear(): void {
    this.localSettings = {
      enabled: this.settings.enabled,
      serverUrl: this.settings.serverUrl,
      username: this.settings.username,
      password: this.settings.password,
      basePath: this.settings.basePath,
      autoBackup: this.settings.autoBackup,
      autoBackupInterval: this.settings.autoBackupInterval,
      keepBackupCount: this.settings.keepBackupCount,
      lastSyncTime: this.settings.lastSyncTime,
      connectionStatus: this.settings.connectionStatus || 'untested',
      lastTestTime: this.settings.lastTestTime || 0,
      lastTestMessage: this.settings.lastTestMessage || '',
      needCreateDir: this.settings.needCreateDir || false
    };
    
    // 如果有上次测试结果，显示它
    if (this.localSettings.lastTestMessage) {
      const statusIcon = this.localSettings.connectionStatus === 'success' ? '✅' : 
                         this.localSettings.connectionStatus === 'failed' ? '❌' : '❓';
      this.testResult = `${statusIcon} ${this.localSettings.lastTestMessage}`;
    }
  }

  async testConnection(): Promise<void> {
    this.isTesting = true;
    this.testResult = '';

    try {
      const result = await this.onTest(this.localSettings);
      if (result.success) {
        if (result.needCreateDir) {
          this.testResult = `⚠️ ${result.message}`;
          this.pendingSettings = this.localSettings;
          this.showCreateDirDialog = true;
        } else {
          this.testResult = `✅ ${result.message}`;
          // 测试成功，更新连接状态
          this.localSettings.connectionStatus = 'success';
          this.localSettings.lastTestTime = Date.now();
          this.localSettings.lastTestMessage = result.message;
          this.localSettings.needCreateDir = false;
        }
      } else {
        this.testResult = `❌ ${result.message}`;
        // 测试失败，更新状态
        this.localSettings.connectionStatus = 'failed';
        this.localSettings.lastTestTime = Date.now();
        this.localSettings.lastTestMessage = result.message;
        this.localSettings.needCreateDir = result.needCreateDir;
      }
    } catch (error) {
      this.testResult = `❌ ${error}`;
      this.localSettings.connectionStatus = 'failed';
      this.localSettings.lastTestTime = Date.now();
      this.localSettings.lastTestMessage = String(error);
    } finally {
      this.isTesting = false;
    }
  }

  async createDirectoryAndConfirm(): Promise<void> {
    if (!this.pendingSettings) return;
    
    try {
      this.isTesting = true;
      this.showCreateDirDialog = false;
      
      // 设置enabled为true，表示需要创建目录
      const settingsWithCreate: WebDAVSettings = {
        enabled: true,
        serverUrl: this.pendingSettings.serverUrl,
        username: this.pendingSettings.username,
        password: this.pendingSettings.password,
        basePath: this.pendingSettings.basePath,
        autoBackup: this.pendingSettings.autoBackup,
        autoBackupInterval: this.pendingSettings.autoBackupInterval,
        keepBackupCount: this.pendingSettings.keepBackupCount,
        lastSyncTime: this.pendingSettings.lastSyncTime,
        connectionStatus: 'success',
        lastTestTime: Date.now(),
        lastTestMessage: '连接成功，目录已创建',
        needCreateDir: true
      };
      
      // 调用onConfirm，让父组件创建目录并保存配置
      this.onConfirm(settingsWithCreate);
      this.pendingSettings = null;
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      this.testResult = `❌ 创建目录失败: ${errorMsg}`;
    } finally {
      this.isTesting = false;
    }
  }

  @Builder
  buildCreateDirDialog() {
    Column() {
      Column() {
        Text('创建备份目录')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
          .margin({ bottom: 16 })

        Text(`服务器连接成功！\n\n为了使用WebDAV备份功能，需要在服务器上创建专用目录：\n\n${this.localSettings.basePath}\n\n是否立即创建？`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
          .lineHeight(22)
          .margin({ bottom: 24 })

        Row() {
          Button('取消')
            .fontSize(16)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
            .borderRadius(8)
            .layoutWeight(1)
            .onClick(() => {
              this.showCreateDirDialog = false;
              this.pendingSettings = null;
            })

          Blank().width(16)

          Button('创建')
            .fontSize(16)
            .fontColor('#FFFFFF')
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
            .borderRadius(8)
            .layoutWeight(1)
            .onClick(() => {
              this.createDirectoryAndConfirm();
            })
        }
        .width('100%')
      }
      .width('80%')
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.currentTheme))
      .borderRadius(16)
      .padding(24)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0, 0, 0, 0.5)')
    .justifyContent(FlexAlign.Center)
  }


  @Builder
  buildInputItem(label:
    string, placeholder:
    string, value:
    string, onChange:
    (value: string) => void
  )
  {
    Column() {
      Text(label)
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
        .width('100%')
        .margin({ bottom: 8 })

      TextInput({ text: value, placeholder: placeholder })
        .width('100%')
        .onChange(onChange)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
        .borderRadius(8)
    }
    .width('100%')
    .margin({ bottom: 16 })
    .alignItems(HorizontalAlign.Start)
  }


  @Builder
  buildPasswordItem() {
    Column() {
      Text('密码')
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
        .width('100%')
        .margin({ bottom: 8 })

      Row() {
        TextInput({ text: this.localSettings.password, placeholder: '输入密码' })
          .type(this.showPassword ? InputType.Normal : InputType.Password)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.localSettings.password = value;
          })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
          .borderRadius(8)

        Button(this.showPassword ? '隐藏' : '显示')
          .fontSize(12)
          .margin({ left: 8 })
          .onClick(() => {
            this.showPassword = !this.showPassword;
          })
      }
      .width('100%')
    }
    .width('100%')
    .margin({ bottom: 16 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildIntervalButton(label:string, value:'manual' | 'daily' | 'weekly')
  {
    Button(label)
      .fontSize(12)
      .padding({
        left: 12,
        right: 12,
        top: 6,
        bottom: 6
      })
      .margin({ left: 4, right: 4 })
      .backgroundColor(
        this.localSettings.autoBackupInterval === value
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme)
      )
      .fontColor(
        this.localSettings.autoBackupInterval === value
          ? '#FFFFFF'
          : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme)
      )
      .onClick(() => {
        this.localSettings.autoBackupInterval = value;
      })
  }

  build() {
    Stack() {
      Column() {
        Column() {
          // 标题栏
          Row() {
            Text('WebDAV配置')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
              .layoutWeight(1)

            // 启用开关
            Row() {
              Text('启用')
                .fontSize(14)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
                .margin({ right: 8 })

              Toggle({ type: ToggleType.Switch, isOn: this.localSettings.enabled })
                .onChange((isOn: boolean) => {
                  this.localSettings.enabled = isOn;
                })
            }
          }
          .width('100%')
          .padding({ top: 20, bottom: 16 })

          // 配置表单
          Scroll() {
            Column() {
              // 服务器地址
              this.buildInputItem(
                '服务器地址',
                'https://cloud.example.com/remote.php/dav',
                this.localSettings.serverUrl,
                (value: string) => {
                  this.localSettings.serverUrl = value;
                }
              )

              // 用户名
              this.buildInputItem(
                '用户名',
                '输入用户名',
                this.localSettings.username,
                (value: string) => {
                  this.localSettings.username = value;
                }
              )

              // 密码
              this.buildPasswordItem()

              // 基础路径
              this.buildInputItem(
                '基础路径',
                '/manxia',
                this.localSettings.basePath,
                (value: string) => {
                  this.localSettings.basePath = value;
                }
              )

              Divider()
                .margin({ top: 16, bottom: 16 })
                .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))

              // 自动备份设置
              Text('自动备份')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
                .margin({ bottom: 12 })

              Row() {
                Text('启用自动备份')
                  .fontSize(14)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
                  .layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: this.localSettings.autoBackup })
                  .onChange((isOn: boolean) => {
                    this.localSettings.autoBackup = isOn;
                  })
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })

              if (this.localSettings.autoBackup) {
                // 备份间隔
                Row() {
                  Text('备份间隔')
                    .fontSize(14)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
                    .layoutWeight(1)

                  Row() {
                    this.buildIntervalButton('手动', 'manual')
                    this.buildIntervalButton('每天', 'daily')
                    this.buildIntervalButton('每周', 'weekly')
                  }
                }
                .width('100%')
                .padding({ top: 8, bottom: 8 })

                // 保留备份数量
                Row() {
                  Text('保留备份数量')
                    .fontSize(14)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
                    .layoutWeight(1)

                  Row() {
                    Button('-')
                      .fontSize(16)
                      .width(40)
                      .height(32)
                      .onClick(() => {
                        if (this.localSettings.keepBackupCount > 1) {
                          this.localSettings.keepBackupCount--;
                        }
                      })

                    Text(`${this.localSettings.keepBackupCount}`)
                      .fontSize(16)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
                      .width(40)
                      .textAlign(TextAlign.Center)

                    Button('+')
                      .fontSize(16)
                      .width(40)
                      .height(32)
                      .onClick(() => {
                        if (this.localSettings.keepBackupCount < 20) {
                          this.localSettings.keepBackupCount++;
                        }
                      })
                  }
                }
                .width('100%')
                .padding({ top: 8, bottom: 8 })
              }

              // 测试连接按钮
              Button(this.isTesting ? '测试中...' : '测试连接')
                .width('100%')
                .margin({ top: 16 })
                .onClick(() => {
                  this.testConnection();
                })

              // 测试结果
              if (this.testResult) {
                Text(this.testResult)
                  .fontSize(14)
                  .fontColor(this.testResult.includes('✅') ? '#00C853' : '#FF5252')
                  .margin({ top: 8 })
                  .width('100%')
                  .textAlign(TextAlign.Center)
              }
            }
            .width('100%')
            .padding(16)
          }
          .layoutWeight(1)
          .scrollBar(BarState.Auto)

          // 底部按钮
          Row() {
            Button('取消')
              .fontSize(16)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
              .borderRadius(8)
              .layoutWeight(1)
              .onClick(() => {
                this.onCancel();
              })

            Blank().width(16)

            Button('保存')
              .fontSize(16)
              .fontColor('#FFFFFF')
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
              .borderRadius(8)
              .layoutWeight(1)
              .onClick(() => {
                this.onConfirm(this.localSettings);
              })
          }
          .width('100%')
          .padding({ top: 16, bottom: 20 })
        }
        .width('90%')
        .height('80%')
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.currentTheme))
        .borderRadius(16)
        .padding({ left: 20, right: 20 })
        .scale({ x: 1, y: 1 })
        .opacity(1)
        .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.EaseOut })
          .combine(TransitionEffect.scale({ x: 0.9, y: 0.9 }).animation({ duration: 300, curve: Curve.EaseOut })))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }))

      // 创建目录确认对话框
      if (this.showCreateDirDialog) {
        this.buildCreateDirDialog()
      }
    }
  }
}