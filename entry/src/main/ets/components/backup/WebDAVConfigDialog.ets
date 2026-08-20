/**
 * WebDAV配置对话框
 * 玻璃效果 + 网络扫描 + 与网络文件夹页面同风格布局
 *
 * 文件路径: entry/src/main/ets/components/backup/WebDAVConfigDialog.ets
 */

import { ThemeAwareHelper } from '../../Framework/Components/ThemeAware';
import { ThemeType } from '../../Framework/Managers/ThemeManager';
import { WebDAVSettings } from '../../Models/WebDAVModels';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { WebDAVTestResult } from 'manxia_network/src/main/ets/Framework/WebDAV/WebDAVClient';
import { WebDAVErrorAnalyzer, WEBDAV_SERVER_GUIDES, WebDAVServerGuide } from 'manxia_network/src/main/ets/Framework/WebDAV/WebDAVErrorAnalyzer';
import { getAutoBackupScheduler, formatNextBackupTime, AutoBackupStatus } from '../../Framework/WebDAV/WebDAVAutoBackupScheduler';
import { SettingsPanelSurfaceHelper } from '../../pages/settings/SettingsPanelSurfaceHelper';
import { NetworkScannerAdapter } from '../../Framework/Network/NetworkScannerAdapter';
import { NetworkScanHost, ProtocolPort } from '../../Models/NetworkFolderModels';

const TAG = 'WebDAVConfigDialog';
const ACCENT_COLOR: string = '#0F8A6C';

@ComponentV2
export struct WebDAVConfigDialog {
  @Param @Require onConfirm: (settings: WebDAVSettings) => void;
  @Param @Require onCancel: () => void;
  @Param @Require onTest: (settings: WebDAVSettings) => Promise<WebDAVTestResult>;
  @Param @Require currentTheme: ThemeType;
  @Param appFontFamily: string = 'HarmonyOS Sans';
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

  // 独立的自动备份设置状态
  @Local autoBackupEnabled: boolean = false;
  @Local autoBackupInterval: 'daily' | 'weekly' = 'daily';
  @Local keepBackupCount: number = 5;

  // 动画状态
  @Local isVisible: boolean = false;
  @Local dialogScale: number = 0.96;
  @Local dialogOpacity: number = 0;
  @Local backdropOpacity: number = 0;
  @Local dialogTranslateY: number = 24;

  // 网络扫描状态
  @Local scanPhase: string = 'idle'; // 'idle' | 'scanning' | 'done'
  @Local scanSubnet: string = '';
  @Local scanProgress: number = 0;
  @Local scanTotal: number = 254;
  @Local scanCurrentIP: string = '';
  @Local scanResults: NetworkScanHost[] = [];
  @Local scanDurationMs: number = 0;
  private scanStartTime: number = 0;
  private scannerAdapter: NetworkScannerAdapter = new NetworkScannerAdapter();

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

    this.autoBackupEnabled = this.settings.autoBackup;
    this.autoBackupInterval = this.settings.autoBackupInterval as 'daily' | 'weekly';
    this.keepBackupCount = this.settings.keepBackupCount;

    if (this.localSettings.lastTestMessage) {
      const statusIcon = this.localSettings.connectionStatus === 'success' ? '✅' :
                         this.localSettings.connectionStatus === 'failed' ? '❌' : '❓';
      this.testResult = `${statusIcon} ${this.localSettings.lastTestMessage}`;
    }

    if (this.localSettings.serverUrl) {
      this.detectedServerType = WebDAVErrorAnalyzer.detectServerType(this.localSettings.serverUrl);
    }

    this.loadAutoBackupStatus();

    // 检测子网前缀
    if (this.scannerAdapter.isAvailable()) {
      const subnet = this.scannerAdapter.getLocalSubnet();
      this.scanSubnet = subnet.length > 0 ? subnet : '192.168.1';
    }

    // 播放出现动画，动画完成后自动开始扫描
    setTimeout(() => {
      this.playEnterAnimation();
      if (this.scanSubnet.trim().length > 0) {
        setTimeout(() => {
          this.startNetworkScan();
        }, 300);
      }
    }, 16);
  }

  private playEnterAnimation(): void {
    this.getUIContext().animateTo({
      duration: 260,
      curve: Curve.EaseOut
    }, () => {
      this.isVisible = true;
      this.dialogScale = 1;
      this.dialogOpacity = 1;
      this.backdropOpacity = 1;
      this.dialogTranslateY = 0;
    });
  }

  private playExitAnimation(callback: () => void): void {
    this.getUIContext().animateTo({
      duration: 180,
      curve: Curve.EaseIn,
      onFinish: () => {
        callback();
      }
    }, () => {
      this.isVisible = false;
      this.dialogScale = 0.96;
      this.dialogOpacity = 0;
      this.backdropOpacity = 0;
      this.dialogTranslateY = 24;
    });
  }

  private closeDialog(): void {
    if (this.scannerAdapter.isScanning()) {
      this.scannerAdapter.stopScan();
    }
    this.playExitAnimation(() => {
      this.onCancel();
    });
  }

  private saveAndClose(): void {
    const settings = this.getMergedSettings();
    this.playExitAnimation(() => {
      this.onConfirm(settings);
    });
  }

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
          this.localSettings.connectionStatus = 'success';
          this.localSettings.lastTestTime = Date.now();
          this.localSettings.lastTestMessage = result.message;
          this.localSettings.needCreateDir = false;
        }
      } else {
        this.testResult = `❌ ${result.message}`;
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

      this.onConfirm(settingsWithCreate);
      this.pendingSettings = null;
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      this.testResult = `❌ 创建目录失败: ${errorMsg}`;
    } finally {
      this.isTesting = false;
    }
  }

  // ==================== 网络扫描 ====================

  private startNetworkScan(): void {
    if (this.scanSubnet.trim().length === 0) {
      return;
    }
    this.scanPhase = 'scanning';
    this.scanResults = [];
    this.scanProgress = 0;
    this.scanTotal = 254;
    this.scanCurrentIP = '';
    this.scanStartTime = Date.now();
    this.scanDurationMs = 0;

    const started = this.scannerAdapter.startScan(
      this.scanSubnet.trim(),
      (scanned: number, total: number, currentIP: string) => {
        this.scanProgress = scanned;
        this.scanTotal = total;
        this.scanCurrentIP = currentIP;
        this.scanDurationMs = Date.now() - this.scanStartTime;
      },
      (host: NetworkScanHost) => {
        // 只保留 WebDAV / WebDAVS 协议的结果
        const hasWebDAV = host.protocolPorts.some(
          (pp: ProtocolPort) => pp.protocol === 3 || pp.protocol === 4
        );
        if (hasWebDAV) {
          this.scanResults = [...this.scanResults, host];
        }
      },
      (_cancelled: boolean) => {
        this.scanDurationMs = Date.now() - this.scanStartTime;
        this.scanPhase = 'done';
      }
    );

    if (!started) {
      this.scanPhase = 'idle';
    }
  }

  private cancelNetworkScan(): void {
    this.scannerAdapter.stopScan();
    this.scanPhase = 'done';
  }

  private applyScanResult(host: NetworkScanHost): void {
    // 优先使用 WebDAVS，其次 WebDAV
    const webdavsEntry = host.protocolPorts.find((pp: ProtocolPort) => pp.protocol === 4);
    const webdavEntry = host.protocolPorts.find((pp: ProtocolPort) => pp.protocol === 3);

    if (webdavsEntry) {
      this.localSettings.serverUrl = `https://${host.ip}:${webdavsEntry.port}`;
    } else if (webdavEntry) {
      this.localSettings.serverUrl = `http://${host.ip}:${webdavEntry.port}`;
    }

    if (this.localSettings.serverUrl.length > 10) {
      this.detectedServerType = WebDAVErrorAnalyzer.detectServerType(this.localSettings.serverUrl);
    }

    // 重置扫描面板
    this.scanPhase = 'idle';
    this.scanResults = [];
  }

  // ==================== 颜色辅助 ====================

  private color(type: 'background' | 'panel_background' | 'comp_background_tertiary' | 'comp_background_secondary' |
    'text_primary' | 'text_secondary' | 'text_muted' | 'text_white' | 'text_black' | 'button_secondary' |
    'button_text_secondary' | 'icon_primary' | 'accent_primary'): Resource {
    return ThemeAwareHelper.getTestManagementThemedColor(type, this.currentTheme);
  }

  // ==================== UI 构建 ====================

  @Builder
  buildDialogField(icon: Resource, label: string, placeholder: string, value: string,
    onChange: (value: string) => void, type: InputType = InputType.Normal) {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        SymbolGlyph(icon)
          .fontSize(14)
          .fontColor([this.color('text_secondary')])
        Text(label)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_secondary'))
      }
      .width('100%')

      TextInput({ text: value, placeholder: placeholder })
        .type(type)
        .height(44)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_primary'))
        .placeholderColor(this.color('text_muted'))
        .backgroundColor(this.color('comp_background_tertiary'))
        .borderRadius(12)
        .padding({ left: 12, right: 12 })
        .onChange((nextValue: string) => {
          onChange(nextValue);
        })
    }
    .width('100%')
  }

  @Builder
  buildActionButton(label: string, icon: Resource, styleKind: number, enabled: boolean,
    onClick: () => void) {
    Button() {
      Row({ space: 6 }) {
        SymbolGlyph(icon)
          .fontSize(14)
          .fontColor([enabled ? this.getActionForegroundColor(styleKind) : this.color('text_muted')])
        Text(label)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(enabled ? this.getActionForegroundColor(styleKind) : this.color('text_muted'))
      }
    }
    .height(36)
    .borderRadius(12)
    .enabled(enabled)
    .backgroundColor(enabled ? this.getActionBackgroundColor(styleKind) : this.color('comp_background_secondary'))
    .padding({ left: 12, right: 12 })
    .onClick(() => {
      onClick();
    })
  }

  private getActionForegroundColor(style: number): ResourceColor {
    if (style === 1) return this.color('text_white');
    if (style === 3) return this.color('text_white');
    return this.color('text_primary');
  }

  private getActionBackgroundColor(style: number): ResourceColor {
    if (style === 1) return this.color('accent_primary');
    if (style === 2) return this.color('comp_background_tertiary');
    if (style === 3) return '#C74848';
    return this.color('button_secondary');
  }

  @Builder
  buildStatusCard() {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        Column() {
          if (this.isTesting) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color(ACCENT_COLOR)
          } else {
            SymbolGlyph($r('sys.symbol.info_circle'))
              .fontSize(16)
              .fontColor([this.color('accent_primary')])
          }
        }
        .width(28)
        .height(28)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.color('comp_background_tertiary'))
        .borderRadius(14)

        Column({ space: 2 }) {
          Text('状态信息')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_secondary'))
            .width('100%')
          Text(this.testResult.length > 0 ? this.testResult : '尚未测试连接')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.color('comp_background_secondary'))
    .borderRadius(16)
  }

  @Builder
  buildScanPanel() {
    Column({ space: 10 }) {
      // 扫描标题栏
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.wifi_router'))
          .fontSize(16)
          .fontColor([this.color('accent_primary')])
        Text('网络扫描')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_primary'))
        Blank()
        if (this.scanPhase === 'scanning') {
          Button() {
            Row({ space: 4 }) {
              LoadingProgress()
                .width(12)
                .height(12)
                .color(this.color('text_white'))
              Text('停止')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
            }
          }
          .height(28)
          .borderRadius(14)
          .backgroundColor(this.color('accent_primary'))
          .fontColor(this.color('text_white'))
          .padding({ left: 10, right: 10 })
          .onClick(() => {
            this.cancelNetworkScan();
          })
        } else {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(14)
            .fontColor([this.color('text_secondary')])
            .onClick(() => {
              this.scanPhase = 'idle';
              this.scanResults = [];
            })
        }
      }
      .width('100%')

      // 子网输入
      if (this.scanPhase === 'idle') {
        Row({ space: 8 }) {
          TextInput({ text: this.scanSubnet, placeholder: '子网前缀 (如 192.168.1)' })
            .layoutWeight(1)
            .height(36)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .backgroundColor(this.color('comp_background_tertiary'))
            .borderRadius(10)
            .onChange((value: string) => {
              this.scanSubnet = value;
            })
          Button('扫描')
            .height(36)
            .borderRadius(10)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .backgroundColor(this.color('accent_primary'))
            .fontColor(this.color('text_white'))
            .padding({ left: 12, right: 12 })
            .onClick(() => {
              this.startNetworkScan();
            })
        }
        .width('100%')
      }

      // 扫描进度
      if (this.scanPhase === 'scanning') {
        Column({ space: 6 }) {
          Progress({
            value: this.scanProgress,
            total: this.scanTotal,
            type: ProgressType.Linear
          })
            .width('100%')
            .height(6)
            .borderRadius(3)
          Row() {
            Text(`${this.scanProgress}/${this.scanTotal}`)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(this.color('text_secondary'))
            Blank()
            if (this.scanResults.length > 0) {
              Row({ space: 3 }) {
                SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                  .fontSize(11)
                  .fontColor([this.color('accent_primary')])
                Text(`已发现 ${this.scanResults.length} 台`)
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.color('accent_primary'))
              }
            }
            Text(`${this.scanDurationMs}ms`)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(this.color('text_muted'))
              .margin({ left: 8 })
          }
          .width('100%')

          Row({ space: 4 }) {
            LoadingProgress()
              .width(10)
              .height(10)
              .color(this.color('accent_primary'))
            Text(`正在扫描: ${this.scanCurrentIP}`)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(this.color('text_muted'))
          }
          .width('100%')
        }
        .width('100%')
      }

      // 扫描完成
      if (this.scanPhase === 'done') {
        Row({ space: 6 }) {
          SymbolGlyph(this.scanResults.length > 0
            ? $r('sys.symbol.checkmark_circle_fill')
            : $r('sys.symbol.magnifyingglass'))
            .fontSize(14)
            .fontColor([this.color('accent_primary')])
          Text(this.scanResults.length > 0
            ? `发现 ${this.scanResults.length} 台WebDAV服务器`
            : '未发现WebDAV服务器')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_secondary'))
          Blank()
          Text(`${this.scanDurationMs}ms`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_muted'))
        }
        .width('100%')
        .padding({ top: 6, bottom: 6 })
      }

      // 扫描结果列表
      if (this.scanResults.length > 0) {
        Column({ space: 6 }) {
          ForEach(this.scanResults, (host: NetworkScanHost) => {
            Row({ space: 10 }) {
              Column() {
                SymbolGlyph($r('sys.symbol.externaldrive_fill'))
                  .fontSize(16)
                  .fontColor([this.color('accent_primary')])
              }
              .width(30)
              .height(30)
              .justifyContent(FlexAlign.Center)
              .backgroundColor(this.color('comp_background_tertiary'))
              .borderRadius(8)

              Column({ space: 2 }) {
                Text(host.ip)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.color('text_primary'))
                Row({ space: 4 }) {
                  ForEach(host.protocolPorts.filter(
                    (pp: ProtocolPort) => pp.protocol === 3 || pp.protocol === 4
                  ), (pp: ProtocolPort) => {
                    Text(`${pp.protocol === 4 ? 'WebDAVS' : 'WebDAV'}:${pp.port}`)
                      .fontSize(10)
                      .fontFamily(this.appFontFamily)
                      .fontColor(this.color('accent_primary'))
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .backgroundColor(this.color('comp_background_tertiary'))
                      .borderRadius(4)
                  }, (pp: ProtocolPort) => `${pp.protocol}_${pp.port}`)
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Button('使用')
                .height(28)
                .borderRadius(8)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .backgroundColor(this.color('accent_primary'))
                .fontColor(this.color('text_white'))
                .padding({ left: 10, right: 10 })
                .onClick(() => {
                  this.applyScanResult(host);
                })
            }
            .width('100%')
            .padding(10)
            .backgroundColor(this.color('comp_background_secondary'))
            .borderRadius(12)
          }, (host: NetworkScanHost) => host.ip)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.color('comp_background_secondary'))
    .borderRadius(16)
  }

  @Builder
  buildServerGuideDialog() {
    Column() {
      Column() {
        Row() {
          Text('服务器配置指南')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_primary'))
          Blank()
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([this.color('text_secondary')])
            .onClick(() => { this.showServerGuide = false; })
        }
        .width('100%')
        .margin({ bottom: 16 })

        Text('选择您的WebDAV服务器类型：')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_secondary'))
          .margin({ bottom: 12 })

        Scroll() {
          Column({ space: 8 }) {
            ForEach(WEBDAV_SERVER_GUIDES, (guide: WebDAVServerGuide) => {
              Column() {
                Row() {
                  Text(guide.name)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontFamily(this.appFontFamily)
                    .fontColor(this.color('text_primary'))
                  Blank()
                  if (this.selectedServerType === guide.name) {
                    SymbolGlyph($r('sys.symbol.checkmark'))
                      .fontSize(16)
                      .fontColor([this.color('accent_primary')])
                  }
                }
                .width('100%')

                if (this.selectedServerType === guide.name) {
                  Column({ space: 4 }) {
                    Text(`地址格式：${guide.urlFormat}`)
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(this.color('text_secondary'))
                      .width('100%')
                    Text(`示例：${guide.example}`)
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(this.color('accent_primary'))
                      .width('100%')
                    Text('注意事项：')
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontFamily(this.appFontFamily)
                      .fontColor(this.color('text_secondary'))
                      .width('100%')
                      .margin({ top: 8 })
                    ForEach(guide.notes, (note: string, idx: number) => {
                      Text(`${idx + 1}. ${note}`)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(this.color('text_muted'))
                        .width('100%')
                    })
                  }
                  .width('100%')
                  .margin({ top: 8 })
                  .padding(12)
                  .backgroundColor(this.color('comp_background_tertiary'))
                  .borderRadius(8)
                }
              }
              .width('100%')
              .padding(12)
              .backgroundColor(
                this.selectedServerType === guide.name
                  ? this.color('comp_background_secondary')
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

        Row({ space: 10 }) {
          this.buildActionButton('关闭', $r('sys.symbol.xmark'), 0, true, () => {
            this.showServerGuide = false;
          })
        }
        .width('100%')
        .margin({ top: 16 })
      }
      .width('90%')
      .height('80%')
      .backgroundColor(this.color('panel_background'))
      .borderRadius(26)
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
            .fontFamily(this.appFontFamily)
            .fontColor('#FF9800')
            .margin({ left: 6 })
          Blank()
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(14)
            .fontColor([this.color('text_muted')])
            .onClick(() => { this.showHelpTips = false; })
        }
        .width('100%')

        Text('大多数WebDAV服务器不允许在根目录创建文件夹，请先在服务器上手动创建备份目录（如 /manxia）。如使用坚果云，必须使用"应用密码"而非登录密码。')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_secondary'))
          .width('100%')

        Button('查看配置指南')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('accent_primary'))
          .backgroundColor('transparent')
          .padding({ left: 0 })
          .onClick(() => { this.showServerGuide = true; })
      }
      .width('100%')
      .padding(12)
      .backgroundColor('rgba(255, 152, 0, 0.08)')
      .borderRadius(12)
    }
  }

  @Builder
  buildCreateDirDialog() {
    Column() {
      Column({ space: 16 }) {
        Row() {
          Text('创建备份目录')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_primary'))
          Blank()
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([this.color('text_secondary')])
            .onClick(() => {
              this.showCreateDirDialog = false;
              this.pendingSettings = null;
            })
        }
        .width('100%')

        Text(`服务器连接成功！\n\n为了使用WebDAV备份功能，需要在服务器上创建专用目录：\n\n${this.localSettings.basePath}\n\n如果自动创建失败，请在服务器上手动创建该目录后重试。`)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_secondary'))
          .lineHeight(22)

        Row({ space: 10 }) {
          this.buildActionButton('取消', $r('sys.symbol.xmark'), 0, true, () => {
            this.showCreateDirDialog = false;
            this.pendingSettings = null;
          })
          this.buildActionButton('创建目录', $r('sys.symbol.folder_badge_plus'), 1, true, () => {
            void this.createDirectoryAndConfirm();
          })
        }
        .width('100%')
      }
      .width('85%')
      .padding(24)
      .backgroundColor(this.color('panel_background'))
      .borderRadius(26)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0, 0, 0, 0.5)')
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 背景遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(`rgba(6, 12, 18, ${0.52 * this.backdropOpacity})`)
        .onClick(() => {
          this.closeDialog();
        })

      // 主面板 - 玻璃效果
      Column({ space: 14 }) {
        // 标题区域
        Row() {
          Column({ space: 4 }) {
            Text('WebDAV 配置')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor(this.color('text_primary'))
            Text('配置WebDAV服务器连接，支持自动云端备份。')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(this.color('text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)

          Blank()

          // 启用开关
          Row({ space: 8 }) {
            Text(this.localSettings.enabled ? '已启用' : '未启用')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(this.localSettings.enabled ? this.color('accent_primary') : this.color('text_muted'))
            Toggle({ type: ToggleType.Switch, isOn: this.localSettings.enabled })
              .onChange((isOn: boolean) => {
                this.localSettings.enabled = isOn;
              })
          }
        }
        .width('100%')

        Divider()
          .color(this.color('text_muted'))
          .opacity(0.3)

        // 表单区域
        Scroll() {
          Column({ space: 14 }) {
            // 状态卡片
            this.buildStatusCard()

            // 重要提示
            this.buildImportantTips()

            // 网络扫描面板
            this.buildScanPanel()

            // 服务器类型检测提示
            if (this.detectedServerType && this.localSettings.serverUrl) {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.info_circle'))
                  .fontSize(14)
                  .fontColor([this.color('accent_primary')])
                Text(`检测到：${this.detectedServerType}`)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.color('accent_primary'))
                Blank()
                Text('查看指南')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.color('text_secondary'))
                  .decoration({ type: TextDecorationType.Underline })
                  .onClick(() => {
                    this.selectedServerType = this.detectedServerType;
                    this.showServerGuide = true;
                  })
              }
              .width('100%')
            }

            // 服务器地址
            this.buildDialogField(
              $r('sys.symbol.link'), '服务器地址', 'https://cloud.example.com/remote.php/dav',
              this.localSettings.serverUrl, (value: string) => {
                this.onServerUrlChanged(value);
              })

            // 用户名 + 密码
            Row({ space: 12 }) {
              Column() {
                this.buildDialogField(
                  $r('sys.symbol.person_fill'), '用户名', '输入用户名',
                  this.localSettings.username, (value: string) => {
                    this.localSettings.username = value;
                  })
              }
              .layoutWeight(1)

              Column() {
                this.buildDialogField(
                  $r('sys.symbol.lock_fill'), '密码', '输入密码',
                  this.localSettings.password, (value: string) => {
                    this.localSettings.password = value;
                  }, InputType.Password)
              }
              .layoutWeight(1)
            }
            .width('100%')

            // 基础路径
            this.buildDialogField(
              $r('sys.symbol.folder'), '基础路径（备份目录）', '/manxia',
              this.localSettings.basePath, (value: string) => {
                this.localSettings.basePath = value;
              })

            // 自动备份设置
            Column({ space: 10 }) {
              Row({ space: 10 }) {
                Column() {
                  SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                    .fontSize(18)
                    .fontColor([this.color('accent_primary')])
                }
                .width(34)
                .height(34)
                .justifyContent(FlexAlign.Center)
                .backgroundColor(this.color('comp_background_tertiary'))
                .borderRadius(10)

                Column({ space: 2 }) {
                  Text('自动备份')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontFamily(this.appFontFamily)
                    .fontColor(this.color('text_primary'))
                    .width('100%')
                  Text('定时自动备份数据到WebDAV服务器')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(this.color('text_secondary'))
                    .width('100%')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Toggle({ type: ToggleType.Switch, isOn: this.autoBackupEnabled })
                  .onChange((isOn: boolean) => {
                    this.autoBackupEnabled = isOn;
                  })
              }
              .width('100%')

              if (this.autoBackupEnabled) {
                Divider()
                  .color(this.color('text_muted'))
                  .opacity(0.2)

                // 备份间隔
                Row() {
                  Text('备份间隔')
                    .fontSize(13)
                    .fontFamily(this.appFontFamily)
                    .fontColor(this.color('text_secondary'))
                    .layoutWeight(1)

                  Row({ space: 6 }) {
                    Button('每天')
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                      .borderRadius(8)
                      .backgroundColor(this.autoBackupInterval === 'daily' ?
                        this.color('accent_primary') : this.color('comp_background_tertiary'))
                      .fontColor(this.autoBackupInterval === 'daily' ?
                        this.color('text_white') : this.color('text_primary'))
                      .onClick(() => { this.autoBackupInterval = 'daily'; })
                    Button('每周')
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                      .borderRadius(8)
                      .backgroundColor(this.autoBackupInterval === 'weekly' ?
                        this.color('accent_primary') : this.color('comp_background_tertiary'))
                      .fontColor(this.autoBackupInterval === 'weekly' ?
                        this.color('text_white') : this.color('text_primary'))
                      .onClick(() => { this.autoBackupInterval = 'weekly'; })
                  }
                }
                .width('100%')

                // 下次备份时间
                if (this.autoBackupStatus && this.autoBackupStatus.enabled &&
                    this.localSettings.connectionStatus === 'success') {
                  Row() {
                    Text('下次备份')
                      .fontSize(13)
                      .fontFamily(this.appFontFamily)
                      .fontColor(this.color('text_secondary'))
                    Blank()
                    Text(this.nextBackupTimeText)
                      .fontSize(13)
                      .fontFamily(this.appFontFamily)
                      .fontColor(this.color('accent_primary'))
                  }
                  .width('100%')
                }

                // 警告
                if (this.localSettings.connectionStatus !== 'success') {
                  Row({ space: 6 }) {
                    SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
                      .fontSize(12)
                      .fontColor(['#FF9800'])
                    Text('请先测试连接成功后，自动备份才能生效')
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor('#FF9800')
                  }
                  .width('100%')
                }

                // 保留备份数量
                Row() {
                  Text('保留备份数量')
                    .fontSize(13)
                    .fontFamily(this.appFontFamily)
                    .fontColor(this.color('text_secondary'))
                    .layoutWeight(1)

                  Row({ space: 4 }) {
                    Button('-')
                      .fontSize(16)
                      .width(36)
                      .height(32)
                      .borderRadius(8)
                      .backgroundColor(this.color('comp_background_tertiary'))
                      .fontColor(this.color('text_primary'))
                      .onClick(() => {
                        if (this.keepBackupCount > 1) {
                          this.keepBackupCount--;
                        }
                      })
                    Text(`${this.keepBackupCount}`)
                      .fontSize(16)
                      .fontFamily(this.appFontFamily)
                      .fontColor(this.color('text_primary'))
                      .width(36)
                      .textAlign(TextAlign.Center)
                    Button('+')
                      .fontSize(16)
                      .width(36)
                      .height(32)
                      .borderRadius(8)
                      .backgroundColor(this.color('comp_background_tertiary'))
                      .fontColor(this.color('text_primary'))
                      .onClick(() => {
                        if (this.keepBackupCount < 20) {
                          this.keepBackupCount++;
                        }
                      })
                  }
                }
                .width('100%')
              }
            }
            .width('100%')
            .padding(12)
            .backgroundColor(this.color('comp_background_secondary'))
            .borderRadius(16)

            Blank().height(4)
          }
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)

        // 底部按钮
        Row({ space: 10 }) {
          this.buildActionButton('取消', $r('sys.symbol.xmark'), 0, true, () => {
            this.closeDialog();
          })
          this.buildActionButton(
            this.isTesting ? '测试中…' : '测试连接',
            $r('sys.symbol.checkmark_circle'), 2, !this.isTesting, () => {
              void this.testConnection();
            })
          this.buildActionButton('保存', $r('sys.symbol.save'), 1, true, () => {
            this.saveAndClose();
          })
        }
        .width('100%')
      }
      .width('92%')
      .height('84%')
      .padding({ left: 20, right: 20, top: 20, bottom: 20 })
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.currentTheme))
      .backgroundBlurStyle(
        SettingsPanelSurfaceHelper.getBlurStyle(this.currentTheme),
        SettingsPanelSurfaceHelper.getBlurOptions(this.currentTheme)
      )
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.currentTheme))
      .borderRadius(26)
      .clip(true)
      .border({
        width: SettingsPanelSurfaceHelper.getBorderWidth(this.currentTheme),
        color: SettingsPanelSurfaceHelper.getBorderColor(this.currentTheme)
      })
      .shadow({
        radius: 26,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.currentTheme),
        offsetX: 0,
        offsetY: 10
      })
      .opacity(this.dialogOpacity)
      .scale({ x: this.dialogScale, y: this.dialogScale })
      .translate({ x: 0, y: this.dialogTranslateY })

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
