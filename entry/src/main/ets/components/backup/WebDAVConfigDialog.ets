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
import { WebDAVErrorAnalyzer, WEBDAV_SERVER_GUIDES, WebDAVServerGuide } from '../../Framework/WebDAV/WebDAVErrorAnalyzer';
import { getAutoBackupScheduler, formatNextBackupTime, AutoBackupStatus } from '../../Framework/WebDAV/WebDAVAutoBackupScheduler';

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
    autoBackupInterval: 'daily',
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
    autoBackupInterval: 'daily',
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
  @Local showServerGuide: boolean = false;
  @Local selectedServerType: string = '';
  @Local detectedServerType: string = '';
  @Local showHelpTips: boolean = true;
  @Local autoBackupStatus: AutoBackupStatus | null = null;
  @Local nextBackupTimeText: string = '';
  
  // 独立的自动备份设置状态（为了UI响应式更新）
  @Local autoBackupEnabled: boolean = false;
  @Local autoBackupInterval: 'daily' | 'weekly' = 'daily';
  @Local keepBackupCount: number = 5;
  
  // 动画状态
  @Local isVisible: boolean = false;
  @Local dialogScale: number = 0.9;
  @Local dialogOpacity: number = 0;
  @Local backdropOpacity: number = 0;

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
    
    // 初始化独立的自动备份状态变量
    this.autoBackupEnabled = this.settings.autoBackup;
    this.autoBackupInterval = this.settings.autoBackupInterval as 'daily' | 'weekly';
    this.keepBackupCount = this.settings.keepBackupCount;
    
    // 如果有上次测试结果，显示它
    if (this.localSettings.lastTestMessage) {
      const statusIcon = this.localSettings.connectionStatus === 'success' ? '✅' : 
                         this.localSettings.connectionStatus === 'failed' ? '❌' : '❓';
      this.testResult = `${statusIcon} ${this.localSettings.lastTestMessage}`;
    }
    
    // 检测服务器类型
    if (this.localSettings.serverUrl) {
      this.detectedServerType = WebDAVErrorAnalyzer.detectServerType(this.localSettings.serverUrl);
    }
    
    // 加载自动备份状态
    this.loadAutoBackupStatus();
    
    // 播放出现动画
    setTimeout(() => {
      this.playEnterAnimation();
    }, 16);
  }
  
  /**
   * 播放出现动画
   */
  private playEnterAnimation(): void {
    animateTo({
      duration: 250,
      curve: Curve.EaseOut
    }, () => {
      this.isVisible = true;
      this.dialogScale = 1;
      this.dialogOpacity = 1;
      this.backdropOpacity = 1;
    });
  }
  
  /**
   * 播放消失动画并执行回调
   */
  private playExitAnimation(callback: () => void): void {
    animateTo({
      duration: 200,
      curve: Curve.EaseIn,
      onFinish: () => {
        callback();
      }
    }, () => {
      this.isVisible = false;
      this.dialogScale = 0.9;
      this.dialogOpacity = 0;
      this.backdropOpacity = 0;
    });
  }
  
  /**
   * 关闭对话框（取消）
   */
  private closeDialog(): void {
    this.playExitAnimation(() => {
      this.onCancel();
    });
  }
  
  /**
   * 保存并关闭对话框
   */
  private saveAndClose(): void {
    const settings = this.getMergedSettings();
    this.playExitAnimation(() => {
      this.onConfirm(settings);
    });
  }
  
  /**
   * 获取合并后的设置（将独立状态变量合并回localSettings）
   */
  private getMergedSettings(): WebDAVSettings {
    return {
      enabled: this.localSettings.enabled,
      serverUrl: this.localSettings.serverUrl,
      username: this.localSettings.username,
      password: this.localSettings.password,
      basePath: this.localSettings.basePath,
      autoBackup: this.autoBackupEnabled,
      autoBackupInterval: this.autoBackupInterval,
      keepBackupCount: this.keepBackupCount,
      lastSyncTime: this.localSettings.lastSyncTime,
      connectionStatus: this.localSettings.connectionStatus,
      lastTestTime: this.localSettings.lastTestTime,
      lastTestMessage: this.localSettings.lastTestMessage,
      needCreateDir: this.localSettings.needCreateDir
    };
  }
  
  /**
   * 加载自动备份状态
   */
  private async loadAutoBackupStatus(): Promise<void> {
    try {
      const scheduler = getAutoBackupScheduler();
      this.autoBackupStatus = await scheduler.getStatus();
      if (this.autoBackupStatus && this.autoBackupStatus.enabled) {
        this.nextBackupTimeText = formatNextBackupTime(this.autoBackupStatus.nextBackupTime);
      }
    } catch (error) {
      logger.error(TAG, `加载自动备份状态失败: ${error}`);
    }
  }
  
  /**
   * 当服务器地址变化时检测服务器类型
   */
  private onServerUrlChanged(url: string): void {
    this.localSettings.serverUrl = url;
    if (url.length > 10) {
      this.detectedServerType = WebDAVErrorAnalyzer.detectServerType(url);
    }
  }

  async testConnection(): Promise<void> {
    this.isTesting = true;
    this.testResult = '';

    try {
      const result = await this.onTest(this.getMergedSettings());
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
  buildServerGuideDialog() {
    Column() {
      Column() {
        Row() {
          Text('服务器配置指南')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
          Blank()
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme)])
            .onClick(() => { this.showServerGuide = false; })
        }
        .width('100%')
        .margin({ bottom: 16 })
        
        Text('选择您的WebDAV服务器类型：')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
          .margin({ bottom: 12 })
        
        Scroll() {
          Column({ space: 8 }) {
            ForEach(WEBDAV_SERVER_GUIDES, (guide: WebDAVServerGuide) => {
              Column() {
                Row() {
                  Text(guide.name)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
                  Blank()
                  if (this.selectedServerType === guide.name) {
                    SymbolGlyph($r('sys.symbol.checkmark'))
                      .fontSize(16)
                      .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme)])
                  }
                }
                .width('100%')
                
                if (this.selectedServerType === guide.name) {
                  Column({ space: 4 }) {
                    Text(`地址格式：${guide.urlFormat}`)
                      .fontSize(12)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.currentTheme))
                      .width('100%')
                    Text(`示例：${guide.example}`)
                      .fontSize(12)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
                      .width('100%')
                    Text('注意事项：')
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
                      .width('100%')
                      .margin({ top: 8 })
                    ForEach(guide.notes, (note: string, idx: number) => {
                      Text(`${idx + 1}. ${note}`)
                        .fontSize(12)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.currentTheme))
                        .width('100%')
                    })
                  }
                  .width('100%')
                  .margin({ top: 8 })
                  .padding(12)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
                  .borderRadius(8)
                }
              }
              .width('100%')
              .padding(12)
              .backgroundColor(
                this.selectedServerType === guide.name
                  ? ThemeAwareHelper.getTestManagementThemedColor('background', this.currentTheme)
                  : 'transparent'
              )
              .borderRadius(8)
              .onClick(() => {
                this.selectedServerType = this.selectedServerType === guide.name ? '' : guide.name;
              })
            })
          }
          .width('100%')
        }
        .height('60%')
        .scrollBar(BarState.Auto)
        
        Button('关闭')
          .width('100%')
          .margin({ top: 16 })
          .onClick(() => { this.showServerGuide = false; })
      }
      .width('90%')
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
  buildImportantTips() {
    if (this.showHelpTips) {
      Column({ space: 8 }) {
        Row() {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(16)
            .fontColor(['#FF9800'])
          Text('重要提示')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FF9800')
            .margin({ left: 6 })
          Blank()
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(14)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.currentTheme)])
            .onClick(() => { this.showHelpTips = false; })
        }
        .width('100%')
        
        Text('• 大多数WebDAV服务器不允许在根目录创建文件夹')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
          .width('100%')
        Text('• 请先在服务器上手动创建备份目录（如 /manxia）')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
          .width('100%')
        Text('• 如使用坚果云，必须使用"应用密码"而非登录密码')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
          .width('100%')
          
        Button('查看配置指南')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
          .backgroundColor('transparent')
          .padding({ left: 0 })
          .onClick(() => { this.showServerGuide = true; })
      }
      .width('100%')
      .padding(12)
      .backgroundColor('rgba(255, 152, 0, 0.1)')
      .borderRadius(8)
      .margin({ bottom: 16 })
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

        Text(`服务器连接成功！\n\n为了使用WebDAV备份功能，需要在服务器上创建专用目录：\n\n${this.localSettings.basePath}\n\nℹ️ 注意：如果自动创建失败，请在服务器上手动创建该目录后重试。`)
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

        
      }
      .width('100%')
    }
    .width('100%')
    .margin({ bottom: 16 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildIntervalButton(label:string, value:'daily' | 'weekly')
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
        this.autoBackupInterval === value
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme)
      )
      .fontColor(
        this.autoBackupInterval === value
          ? '#FFFFFF'
          : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme)
      )
      .borderRadius(6)
      .onClick(() => {
        this.autoBackupInterval = value;
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
              // 重要提示
              this.buildImportantTips()
              
              // 服务器类型检测提示
              if (this.detectedServerType && this.localSettings.serverUrl) {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.info_circle'))
                    .fontSize(14)
                    .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme)])
                  Text(`检测到服务器类型：${this.detectedServerType}`)
                    .fontSize(12)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
                  Blank()
                  Text('查看指南')
                    .fontSize(12)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
                    .decoration({ type: TextDecorationType.Underline })
                    .onClick(() => {
                      this.selectedServerType = this.detectedServerType;
                      this.showServerGuide = true;
                    })
                }
                .width('100%')
                .padding({ top: 8, bottom: 8 })
              }
              
              // 服务器地址
              this.buildInputItem(
                '服务器地址',
                'https://cloud.example.com/remote.php/dav',
                this.localSettings.serverUrl,
                (value: string) => {
                  this.onServerUrlChanged(value);
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
              Column() {
                this.buildInputItem(
                  '基础路径（备份目录）',
                  '/manxia',
                  this.localSettings.basePath,
                  (value: string) => {
                    this.localSettings.basePath = value;
                  }
                )
                Text('ℹ请确保该目录在服务器上已存在，或您有权限创建它')
                  .fontSize(11)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.currentTheme))
                  .width('100%')
                  .margin({ top: -12 })
              }

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

                Toggle({ type: ToggleType.Switch, isOn: this.autoBackupEnabled })
                  .onChange((isOn: boolean) => {
                    this.autoBackupEnabled = isOn;
                  })
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })

              if (this.autoBackupEnabled) {
                // 备份间隔
                Row() {
                  Text('备份间隔')
                    .fontSize(14)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
                    .layoutWeight(1)

                  Row({ space: 8 }) {
                    this.buildIntervalButton('每天', 'daily')
                    this.buildIntervalButton('每周', 'weekly')
                  }
                }
                .width('100%')
                .padding({ top: 8, bottom: 8 })
                
                // 显示下次备份时间
                if (this.autoBackupStatus && this.autoBackupStatus.enabled && this.localSettings.connectionStatus === 'success') {
                  Row() {
                    Text('下次自动备份')
                      .fontSize(14)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
                    Blank()
                    Text(this.nextBackupTimeText)
                      .fontSize(14)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
                  }
                  .width('100%')
                  .padding({ top: 4, bottom: 8 })
                }
                
                // 警告提示
                if (this.localSettings.connectionStatus !== 'success') {
                  Text('⚠️ 请先测试连接成功后，自动备份才能生效')
                    .fontSize(12)
                    .fontColor('#FF9800')
                    .width('100%')
                    .padding({ top: 4, bottom: 8 })
                }

                // 保留备份数量
                Row() {
                  Text('保留备份数量')
                    .fontSize(14)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
                    .layoutWeight(1)

                  Row({ space: 4 }) {
                    Button('-')
                      .fontSize(16)
                      .width(36)
                      .height(32)
                      .borderRadius(6)
                      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
                      .onClick(() => {
                        if (this.keepBackupCount > 1) {
                          this.keepBackupCount--;
                        }
                      })

                    Text(`${this.keepBackupCount}`)
                      .fontSize(16)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
                      .width(36)
                      .textAlign(TextAlign.Center)

                    Button('+')
                      .fontSize(16)
                      .width(36)
                      .height(32)
                      .borderRadius(6)
                      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
                      .onClick(() => {
                        if (this.keepBackupCount < 20) {
                          this.keepBackupCount++;
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
                this.closeDialog();
              })

            Blank().width(16)

            Button('保存')
              .fontSize(16)
              .fontColor('#FFFFFF')
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
              .borderRadius(8)
              .layoutWeight(1)
              .onClick(() => {
                this.saveAndClose();
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
        .scale({ x: this.dialogScale, y: this.dialogScale })
        .opacity(this.dialogOpacity)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor(`rgba(0, 0, 0, ${0.5 * this.backdropOpacity})`)

      // 创建目录确认对话框
      if (this.showCreateDirDialog) {
        this.buildCreateDirDialog()
      }
      
      // 服务器配置指南对话框
      if (this.showServerGuide) {
        this.buildServerGuideDialog()
      }
    }
  }
}
