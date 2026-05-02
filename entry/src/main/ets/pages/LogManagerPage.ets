// 文件路径: entry/src/main/ets/pages/LogManagerPage.ets
/**
 * 日志管理页面
 * 显示应用运行日志，支持过滤、搜索和导出功能
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { logger, LogLevel } from '../Utils/Logger';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener } from '../Framework/Managers/DeviceAdaptationManager';
import { LogCollector, LogEntry, LogFilter, LogStats } from '../Framework/Debug/LogCollector';
import { deviceInfo } from '@kit.BasicServicesKit';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';
import { GlobalBackgroundLayerMode } from '../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';

const TAG = 'LogManagerPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

// 使用NavDestinationContext官方类型
// @kit.ArkUI提供的NavDestinationContext已包含必要的类型定义

@Component
struct LogManagerPage {
  @State pathStack: NavPathStack = new NavPathStack();
  private uiContext: UIContext | undefined = undefined;

  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'LogManagerPage';

  // 日志收集器
  private logCollector: LogCollector = LogCollector.getInstance();

  // 日志列表
  @State logs: LogEntry[] = [];
  @State filteredLogs: LogEntry[] = [];
  @State logStats: LogStats = {
    total: 0,
    debug: 0,
    info: 0,
    warn: 0,
    error: 0
  };

  // 设备信息
  @State deviceInfoText: string = '';
  @State showDeviceInfo: boolean = true;

  // 过滤和搜索
  @State filterLevel: LogLevel = LogLevel.DEBUG;
  @State searchText: string = '';
  @State selectedTag: string = '';
  @State isExporting: boolean = false;

  // 缓存的主题颜色（避免在 ForEach 中重复创建 colorMapping 对象导致内存崩溃）
  @State cachedTextWhite: Resource = $r('app.color.test_management_text_white');
  @State cachedAccentBlue: Resource = $r('app.color.test_management_accent_blue');
  @State cachedTextMuted: Resource = $r('app.color.test_management_text_muted');
  @State cachedTextPrimary: Resource = $r('app.color.test_management_text_primary_dark');
  @State cachedTextSecondary: Resource = $r('app.color.test_management_font_secondary_dark');
  @State cachedPanelBg: Resource = $r('app.color.test_management_panel_background');
  @State cachedPanelBorder: Resource = $r('app.color.test_management_panel_border');
  @State cachedAccentOrange: Resource = $r('app.color.test_management_accent_orange');
  @State cachedButtonDanger: Resource = $r('app.color.test_management_button_danger');
  @State cachedBgDark: Resource = $r('app.color.test_management_background_dark');
  @State cachedButtonInactive: Resource = $r('app.color.test_management_button_inactive');
  @State cachedButtonPrimary: Resource = $r('app.color.test_management_button_primary');
  @State cachedAccentGreen: Resource = $r('app.color.test_management_accent_green');
  @State cachedButtonTextSecondary: Resource = $r('app.color.test_management_button_text_secondary_dark');

  // 设备方向
  @State private isLandscape: boolean = false;
  private deviceOrientationListener: DeviceChangeListener | null = null;
  private deviceAdaptationManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private isRefreshPaused: boolean = false;
  private refreshTimerId: number = -1;

  onPageShow(): void {
    try {
      const stack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (stack) {
        this.pathStack = stack;
        logger.debug(TAG, '✅ 成功获取GlobalNavStack');
      }
    } catch (err) {
      logger.error(TAG, 'AppStorage.get 异常', String(err));
    }
    this.loadLogs();
    this.startAutoRefresh();
  }

  private startAutoRefresh(): void {
    this.stopAutoRefresh();
    this.refreshTimerId = this.lifecycle.setInterval(() => {
      if (!this.isRefreshPaused) {
        this.loadLogs();
      }
    }, 3000);
  }

  private stopAutoRefresh(): void {
    if (this.refreshTimerId >= 0) {
      this.lifecycle.clearInterval(this.refreshTimerId);
      this.refreshTimerId = -1;
    }
  }

  onReady(): void {
    // 获取UIContext
    this.uiContext = this.getUIContext();

    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (newTheme: ThemeType) => {
      logger.info(TAG, `主题切换到: ${newTheme}`);
      this.cacheThemeColors();
    });
    this.cacheThemeColors();
    FontAwareHelper.initializeFontAware(this.componentId, this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
    });

    // 初始化设备方向
    const deviceInfo = this.deviceAdaptationManager.getDeviceInfo();
    this.isLandscape = deviceInfo.isLandscape;

    // 注册设备方向监听
    this.deviceOrientationListener = (deviceInfo: DeviceInfo) => {
      // 暂停日志刷新
      this.isRefreshPaused = true;
      
      // 延迟更新方向，等待布局切换完成
      setTimeout(() => {
        this.isLandscape = deviceInfo.isLandscape;
        
        // 再次延迟恢复刷新
        setTimeout(() => {
          this.isRefreshPaused = false;
        }, 300);
      }, 100);
    };
    this.deviceAdaptationManager.addListener(this.deviceOrientationListener);

    // 获取设备信息
    this.loadDeviceInfo();

    // 加载日志
    this.loadLogs();
  }

  /**
   * 加载设备信息
   */
  private loadDeviceInfo(): void {
    try {
      const deviceType = deviceInfo.deviceType || '未知';
      const manufacturer = deviceInfo.manufacture || '未知';
      const brand = deviceInfo.brand || '未知';
      const marketName = deviceInfo.marketName || '未知';
      const productSeries = deviceInfo.productSeries || '未知';
      const productModel = deviceInfo.productModel || '未知';
      const osFullName = deviceInfo.osFullName || '未知';
      const versionId = deviceInfo.versionId || '未知';
      const buildVersion = deviceInfo.buildVersion || '未知';
      const sdkApiVersion = deviceInfo.sdkApiVersion || '未知';
      const distributionOSReleaseType = deviceInfo.distributionOSReleaseType || '未知';
      
      this.deviceInfoText = `设备类型: ${deviceType}\n` +
                           `制造商: ${manufacturer}\n` +
                           `品牌: ${brand}\n` +
                           `市场名称: ${marketName}\n` +
                           `产品系列: ${productSeries}\n` +
                           `产品型号: ${productModel}\n` +
                           `系统版本: ${osFullName}\n` +
                           `版本号: ${versionId}\n` +
                           `构建版本: ${buildVersion}\n` +
                           `SDK API版本: ${sdkApiVersion}\n` +
                           `发行版操作系统类型: ${distributionOSReleaseType}`;
      
      logger.info(TAG, `设备信息加载完成:\n${this.deviceInfoText}`);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, '获取设备信息失败', errorMessage);
      this.deviceInfoText = '设备信息获取失败';
    }
  }

  private lifecycle = new PageLifecycleManager('LogManagerPage', { enableDebug: true });

  aboutToDisappear(): void {
    this.stopAutoRefresh();
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
  }

  private cacheThemeColors(): void {
    const theme = this.themeState.currentTheme;
    this.cachedTextWhite = ThemeAwareHelper.getTestManagementThemedColor('text_white', theme);
    this.cachedAccentBlue = ThemeAwareHelper.getTestManagementThemedColor('accent_blue', theme);
    this.cachedTextMuted = ThemeAwareHelper.getTestManagementThemedColor('text_muted', theme);
    this.cachedTextPrimary = ThemeAwareHelper.getTestManagementThemedColor('text_primary', theme);
    this.cachedTextSecondary = ThemeAwareHelper.getTestManagementThemedColor('text_secondary', theme);
    this.cachedPanelBg = ThemeAwareHelper.getTestManagementThemedColor('panel_background', theme);
    this.cachedPanelBorder = ThemeAwareHelper.getTestManagementThemedColor('panel_border', theme);
    this.cachedAccentOrange = ThemeAwareHelper.getTestManagementThemedColor('accent_orange', theme);
    this.cachedButtonDanger = ThemeAwareHelper.getTestManagementThemedColor('button_danger', theme);
    this.cachedBgDark = ThemeAwareHelper.getTestManagementThemedColor('background_dark', theme);
    this.cachedButtonInactive = ThemeAwareHelper.getTestManagementThemedColor('button_inactive', theme);
    this.cachedButtonPrimary = ThemeAwareHelper.getTestManagementThemedColor('button_primary', theme);
    this.cachedAccentGreen = ThemeAwareHelper.getTestManagementThemedColor('accent_green', theme);
    this.cachedButtonTextSecondary = ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', theme);
  }

  /**
   * 加载日志
   */
  private loadLogs(): void {
    try {
      this.logs = this.logCollector.getAllLogs();
      this.logStats = this.logCollector.getLogStats();
      this.applyFilter();
      logger.info(TAG, `加载了 ${this.logs.length} 条日志`);
    } catch (error) {
      logger.error(TAG, '加载日志失败', String(error));
    }
  }

  /**
   * 应用过滤器
   */
  private applyFilter(): void {
    try {
      const filter: LogFilter = {
        level: this.filterLevel,
        searchText: this.searchText.length > 0 ? this.searchText : undefined,
        tag: this.selectedTag.length > 0 ? this.selectedTag : undefined
      };

      this.filteredLogs = this.logCollector.getFilteredLogs(filter);
      logger.debug(TAG, `过滤后日志数: ${this.filteredLogs.length}`);
    } catch (error) {
      logger.error(TAG, '应用过滤器失败', String(error));
    }
  }

  /**
   * 导出日志为TXT文件
   */
  private async exportLogs(): Promise<void> {
    this.isExporting = true;
    try {
      logger.info(TAG, '开始导出日志');

      // 获取UIAbilityContext
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        throw new Error('无法获取应用上下文');
      }

      // 生成日志内容
      const logContent = this.generateLogContent();
      const fileName = `manxia_logs_${new Date().getTime()}.txt`;

      // 创建临时文件
      const tempFilePath = `${context.cacheDir}/${fileName}`;
      const file = fs.openSync(tempFilePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      fs.writeSync(file.fd, logContent);
      fs.closeSync(file);

      logger.info(TAG, `临时日志文件已创建: ${tempFilePath}`);

      // 使用DocumentViewPicker保存文件
      const documentPicker = new picker.DocumentViewPicker(context);
      const documentSaveOptions = new picker.DocumentSaveOptions();
      documentSaveOptions.newFileNames = [fileName];

      const saveResult = await documentPicker.save(documentSaveOptions);
      
      if (saveResult && saveResult.length > 0) {
        const targetUri = saveResult[0];
        logger.info(TAG, `用户选择保存位置: ${targetUri}`);

        // 复制文件到用户选择的位置
        const tempFile = fs.openSync(tempFilePath, fs.OpenMode.READ_ONLY);
        const targetFile = fs.openSync(targetUri, fs.OpenMode.WRITE_ONLY);
        
        const buffer = new ArrayBuffer(4096);
        let readLen = 0;
        while ((readLen = fs.readSync(tempFile.fd, buffer)) > 0) {
          fs.writeSync(targetFile.fd, buffer, { length: readLen });
        }
        
        fs.closeSync(tempFile);
        fs.closeSync(targetFile);

        logger.info(TAG, `日志导出成功: ${targetUri}`);
      } else {
        logger.info(TAG, '用户取消了保存操作');
      }

      // 清理临时文件
      fs.unlinkSync(tempFilePath);

    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `导出日志失败: ${errorMessage}`);
    } finally {
      this.isExporting = false;
    }
  }

  /**
   * 生成日志内容
   */
  private generateLogContent(): string {
    // 添加设备信息头部
    let content = `========================================\n`;
    content += `漫匣应用日志\n`;
    content += `========================================\n`;
    content += `导出时间: ${new Date().toLocaleString()}\n`;
    content += `日志总数: ${this.filteredLogs.length}\n`;
    content += `\n`;
    content += `========================================\n`;
    content += `设备信息\n`;
    content += `========================================\n`;
    content += `${this.deviceInfoText}\n`;
    content += `========================================\n\n`;

    // 添加日志内容
    for (const log of this.filteredLogs) {
      const timestamp = new Date(log.timestamp).toLocaleString();
      const level = this.getLevelText(log.level);
      content += `[${timestamp}] [${level}] [${log.tag}] ${log.message}`;
      
      if (log.args && log.args.length > 0) {
        content += ` ${log.args.join(' ')}`;
      }
      
      if (log.details) {
        content += `\n  详情: ${log.details}`;
      }
      
      content += '\n';
    }

    return content;
  }

  /**
   * 清空日志
   */
  private clearLogs(): void {
    try {
      this.logCollector.clearLogs();
      this.loadLogs();
      logger.info(TAG, '日志已清空');
    } catch (error) {
      logger.error(TAG, '清空日志失败', String(error));
    }
  }

  private goBack(): void {
    try {
      this.pathStack.pop();
    } catch (error) {
      logger.error(TAG, '返回失败', String(error));
    }
  }

  /**
   * 获取日志级别文本
   */
  private getLevelText(level: LogLevel): string {
    switch (level) {
      case LogLevel.DEBUG:
        return 'DEBUG';
      case LogLevel.INFO:
        return 'INFO';
      case LogLevel.WARN:
        return 'WARN';
      case LogLevel.ERROR:
        return 'ERROR';
      default:
        return 'UNKNOWN';
    }
  }

  /**
   * 获取日志级别颜色
   */
  private getLevelColor(level: LogLevel): ResourceColor {
    switch (level) {
      case LogLevel.DEBUG:
        return this.cachedTextMuted;
      case LogLevel.INFO:
        return this.cachedAccentBlue;
      case LogLevel.WARN:
        return this.cachedAccentOrange;
      case LogLevel.ERROR:
        return this.cachedButtonDanger;
      default:
        return this.cachedTextSecondary;
    }
  }

  /**
   * 构建设备信息卡片
   */
  @Builder
  buildDeviceInfo() {
    Column({ space: 8 }) {
      // 标题栏
      Row({ space: 8 }) {
        Text('📱 设备信息')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.cachedTextPrimary)
          .layoutWeight(1)

        // 折叠/展开按钮
        Text(this.showDeviceInfo ? '收起' : '展开')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.cachedAccentBlue)
          .onClick(() => {
            this.showDeviceInfo = !this.showDeviceInfo;
          })
      }
      .width('100%')

      // 设备信息内容
      if (this.showDeviceInfo) {
        Column({ space: 4 }) {
          ForEach(this.deviceInfoText.split('\n'), (line: string, index: number) => {
            if (line.trim().length > 0) {
              Row({ space: 4 }) {
                Text('•')
                  .fontSize(10)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.cachedAccentBlue)

                Text(line)
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.cachedTextSecondary)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .padding({ left: 4 })
            }
          }, (line: string, index: number) => `${index}-${line}`)
        }
        .width('100%')
        .padding({ top: 8 })
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut }).combine(
            TransitionEffect.translate({ y: -8 }).animation({ duration: 250, curve: Curve.EaseOut })
          ),
          TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseIn }).combine(
            TransitionEffect.translate({ y: -8 }).animation({ duration: 200, curve: Curve.EaseIn })
          )
        ))
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.cachedPanelBg)
    .borderRadius(8)
    .border({ width: 1, color: this.cachedPanelBorder })
    .margin({ left: 16, right: 16, top: 12, bottom: 8 })
  }

  /**
   * 构建统计信息
   */
  @Builder
  buildLogStats() {
    Row({ space: 8 }) {
      Column() {
        Text(`${this.logStats.total}`)
          .fontSize(18)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.cachedTextPrimary)
        Text('全部')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.cachedTextMuted)
      }
      .layoutWeight(1)
      .padding(12)
      .backgroundColor(this.cachedPanelBg)
      .borderRadius(8)

      Column() {
        Text(`${this.logStats.debug}`)
          .fontSize(18)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.cachedTextPrimary)
        Text('调试')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.cachedTextMuted)
      }
      .layoutWeight(1)
      .padding(12)
      .backgroundColor(this.cachedPanelBg)
      .borderRadius(8)

      Column() {
        Text(`${this.logStats.info}`)
          .fontSize(18)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.cachedAccentBlue)
        Text('信息')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.cachedTextMuted)
      }
      .layoutWeight(1)
      .padding(12)
      .backgroundColor(this.cachedPanelBg)
      .borderRadius(8)

      Column() {
        Text(`${this.logStats.warn}`)
          .fontSize(18)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.cachedAccentOrange)
        Text('警告')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.cachedTextMuted)
      }
      .layoutWeight(1)
      .padding(12)
      .backgroundColor(this.cachedPanelBg)
      .borderRadius(8)

      Column() {
        Text(`${this.logStats.error}`)
          .fontSize(18)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.cachedButtonDanger)
        Text('错误')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.cachedTextMuted)
      }
      .layoutWeight(1)
      .padding(12)
      .backgroundColor(this.cachedPanelBg)
      .borderRadius(8)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  /**
   * 构建过滤器
   */
  @Builder
  buildFilter() {
    Column({ space: 12 }) {
      // 搜索框
      TextInput({ placeholder: '搜索日志...', text: this.searchText })
        .width('100%')
        .height(40)
        .backgroundColor(this.cachedPanelBg)
        .onChange((value: string) => {
          this.searchText = value;
          this.applyFilter();
        })

      // 级别过滤
      Row({ space: 8 }) {
        Text('级别:')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(this.cachedTextSecondary)

        Button({ stateEffect: true }) {
          Text('DEBUG')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(this.cachedButtonTextSecondary)
        }
        .width(60)
        .height(28)
        .backgroundColor(
          this.filterLevel === LogLevel.DEBUG
            ? this.cachedTextMuted
            : this.cachedButtonInactive
        )
        .borderRadius(6)
        .onClick(() => { this.filterLevel = LogLevel.DEBUG; this.applyFilter(); })

        Button({ stateEffect: true }) {
          Text('INFO')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(this.cachedButtonTextSecondary)
        }
        .width(55)
        .height(28)
        .backgroundColor(
          this.filterLevel === LogLevel.INFO
            ? this.cachedAccentBlue
            : this.cachedButtonInactive
        )
        .borderRadius(6)
        .onClick(() => { this.filterLevel = LogLevel.INFO; this.applyFilter(); })

        Button({ stateEffect: true }) {
          Text('WARN')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(this.cachedButtonTextSecondary)
        }
        .width(55)
        .height(28)
        .backgroundColor(
          this.filterLevel === LogLevel.WARN
            ? this.cachedAccentOrange
            : this.cachedButtonInactive
        )
        .borderRadius(6)
        .onClick(() => { this.filterLevel = LogLevel.WARN; this.applyFilter(); })

        Button({ stateEffect: true }) {
          Text('ERROR')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(this.cachedButtonTextSecondary)
        }
        .width(60)
        .height(28)
        .backgroundColor(
          this.filterLevel === LogLevel.ERROR
            ? this.cachedButtonDanger
            : this.cachedButtonInactive
        )
        .borderRadius(6)
        .onClick(() => { this.filterLevel = LogLevel.ERROR; this.applyFilter(); })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  /**
   * 构建操作按钮
   */
  @Builder
  buildActionButtons() {
    Row({ space: 12 }) {
      Column() {
        Button({ stateEffect: true }) {
          Text('刷新')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(this.cachedButtonTextSecondary)
        }
          .width('100%')
          .height(36)
          .backgroundColor(this.cachedAccentBlue)
          .borderRadius(8)
          .onClick(() => { this.loadLogs(); })
      }.layoutWeight(1)

      Column() {
        Button({ stateEffect: true }) {
          Text(this.isExporting ? '导出中...' : '导出')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(this.cachedButtonTextSecondary)
        }
          .width('100%')
          .height(36)
          .backgroundColor(this.cachedAccentGreen)
          .borderRadius(8)
          .onClick(() => {
            if (!this.isExporting) {
              this.exportLogs().catch((error: Error) => {
                logger.error(TAG, '导出日志异常', error.message);
              });
            }
          })
      }.layoutWeight(1)

      Column() {
        Button({ stateEffect: true }) {
          Text('清空')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(this.cachedButtonTextSecondary)
        }
          .width('100%')
          .height(36)
          .backgroundColor(this.cachedButtonDanger)
          .borderRadius(8)
          .onClick(() => { this.clearLogs(); })
      }.layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  /**
   * 构建日志列表项
   */
  @Builder
  buildLogItem(log: LogEntry) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Text(this.getLevelText(log.level))
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor(this.cachedTextWhite)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor(this.getLevelColor(log.level))
          .borderRadius(4)

        Text(log.tag)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(this.cachedAccentBlue)
          .fontWeight(FontWeight.Medium)

        Blank()

        Text(new Date(log.timestamp).toLocaleTimeString())
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor(this.cachedTextMuted)
      }
      .width('100%')

      Text(log.message)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.cachedTextPrimary)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (log.args && log.args.length > 0) {
        Text(log.args.join(' '))
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(this.cachedTextSecondary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.cachedPanelBg)
    .borderRadius(8)
    .border({ width: 1, color: this.cachedPanelBorder })
    .margin({ left: 16, right: 16, bottom: 8 })
  }

  build() {
    HdsNavDestination() {
      Stack() {
        SharedPageBackgroundLayer({
          defaultBackgroundColor: this.cachedBgDark,
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        if (this.isLandscape) {
          Column() {
            Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))

            Row() {
              Column() {
                this.buildDeviceInfo()
                this.buildLogStats()
              }
              .width('40%')
              .height('100%')
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

              Column() {
                this.buildFilter()
                this.buildActionButtons()

                if (this.filteredLogs.length === 0) {
                  Column({ space: 20 }) {
                    Text('暂无日志')
                      .fontSize(16)
                      .fontFamily(this.appFontFamily)
                      .fontColor(this.cachedTextMuted)
                  }
                  .width('100%')
                  .layoutWeight(1)
                  .justifyContent(FlexAlign.Center)
                } else {
                  List() {
                    ForEach(this.filteredLogs, (log: LogEntry) => {
                      ListItem() {
                        this.buildLogItem(log)
                      }
                    }, (log: LogEntry) => `${log.id}`)
                  }
                  .width('100%')
                  .layoutWeight(1)
                  .edgeEffect(EdgeEffect.Spring)
                  .scrollBar(BarState.Auto)
                }
              }
              .width('60%')
              .height('100%')
            }
            .width('100%')
            .layoutWeight(1)
          }
          .width('100%')
          .height('100%')
        } else {
          Column() {
            Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))

            this.buildDeviceInfo()
            this.buildLogStats()
            this.buildFilter()
            this.buildActionButtons()

            if (this.filteredLogs.length === 0) {
              Column({ space: 20 }) {
                Text('暂无日志')
                  .fontSize(16)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.cachedTextMuted)
              }
              .width('100%')
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
            } else {
              List() {
                ForEach(this.filteredLogs, (log: LogEntry) => {
                  ListItem() {
                    this.buildLogItem(log)
                  }
                }, (log: LogEntry) => `${log.id}`)
              }
              .width('100%')
              .layoutWeight(1)
              .edgeEffect(EdgeEffect.Spring)
              .scrollBar(BarState.Auto)
            }
          }
          .width('100%')
          .height('100%')
        }

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '日志管理',
          appFontFamily: this.appFontFamily
        })
      }
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor(Color.Transparent)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.onPageShow();
      this.onReady();
    })
  }
}

export { LogManagerPage }
