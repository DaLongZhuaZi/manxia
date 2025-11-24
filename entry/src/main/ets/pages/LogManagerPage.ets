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
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { logger, LogLevel } from '../Utils/Logger';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener } from '../Framework/Managers/DeviceAdaptationManager';
import { LogCollector, LogEntry, LogFilter, LogStats } from '../Framework/Debug/LogCollector';
import { deviceInfo } from '@kit.BasicServicesKit';

const TAG = 'LogManagerPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

// 使用NavDestinationContext官方类型
// @kit.ArkUI提供的NavDestinationContext已包含必要的类型定义

@Component
struct LogManagerPage {
  @State pathStack: NavPathStack = new NavPathStack();
  private scroller: Scroller = new Scroller();
  private uiContext: UIContext | undefined = undefined;

  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
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

  // 设备方向
  @State private isLandscape: boolean = false;
  private deviceOrientationListener: DeviceChangeListener | null = null;
  private deviceAdaptationManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private isRefreshPaused: boolean = false;

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
  }

  onReady(): void {
    // 获取UIContext
    this.uiContext = this.getUIContext();

    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (newTheme: ThemeType) => {
      logger.info(TAG, `主题切换到: ${newTheme}`);
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

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
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
        return ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme);
      case LogLevel.INFO:
        return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme);
      case LogLevel.WARN:
        return ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme);
      case LogLevel.ERROR:
        return ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme);
      default:
        return ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme);
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
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)

        // 折叠/展开按钮
        Text(this.showDeviceInfo ? '收起' : '展开')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
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
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                
                Text(line)
                  .fontSize(11)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
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
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(8)
    .border({ 
      width: 1, 
      color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) 
    })
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
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Text('全部')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .layoutWeight(1)
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(8)

      Column() {
        Text(`${this.logStats.debug}`)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Text('调试')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .layoutWeight(1)
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(8)

      Column() {
        Text(`${this.logStats.info}`)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        Text('信息')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .layoutWeight(1)
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(8)

      Column() {
        Text(`${this.logStats.warn}`)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
        Text('警告')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .layoutWeight(1)
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(8)

      Column() {
        Text(`${this.logStats.error}`)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
        Text('错误')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .layoutWeight(1)
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
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
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .onChange((value: string) => {
          this.searchText = value;
          this.applyFilter();
        })

      // 级别过滤
      Row({ space: 8 }) {
        Text('级别:')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

        Button({ stateEffect: true }) {
          Text('DEBUG')
            .fontSize(11)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
        }
        .width(60)
        .height(28)
        .backgroundColor(
          this.filterLevel === LogLevel.DEBUG
            ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
        )
        .borderRadius(6)
        .onClick(() => { this.filterLevel = LogLevel.DEBUG; this.applyFilter(); })

        Button({ stateEffect: true }) {
          Text('INFO')
            .fontSize(11)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
        }
        .width(55)
        .height(28)
        .backgroundColor(
          this.filterLevel === LogLevel.INFO
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
        )
        .borderRadius(6)
        .onClick(() => { this.filterLevel = LogLevel.INFO; this.applyFilter(); })

        Button({ stateEffect: true }) {
          Text('WARN')
            .fontSize(11)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
        }
        .width(55)
        .height(28)
        .backgroundColor(
          this.filterLevel === LogLevel.WARN
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
        )
        .borderRadius(6)
        .onClick(() => { this.filterLevel = LogLevel.WARN; this.applyFilter(); })

        Button({ stateEffect: true }) {
          Text('ERROR')
            .fontSize(11)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
        }
        .width(60)
        .height(28)
        .backgroundColor(
          this.filterLevel === LogLevel.ERROR
            ? ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
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
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
        }
          .width('100%')
          .height(36)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .borderRadius(8)
          .onClick(() => { this.loadLogs(); })
      }.layoutWeight(1)

      Column() {
        Button({ stateEffect: true }) {
          Text(this.isExporting ? '导出中...' : '导出')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
        }
          .width('100%')
          .height(36)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
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
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
        }
          .width('100%')
          .height(36)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
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
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor(this.getLevelColor(log.level))
          .borderRadius(4)

        Text(log.tag)
          .fontSize(11)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .fontWeight(FontWeight.Medium)

        Blank()

        Text(new Date(log.timestamp).toLocaleTimeString())
          .fontSize(10)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')

      Text(log.message)
        .fontSize(12)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (log.args && log.args.length > 0) {
        Text(log.args.join(' '))
          .fontSize(11)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(8)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
    .margin({ left: 16, right: 16, bottom: 8 })
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 背景区域
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        
        if (this.isLandscape) {
          // 横屏布局：左边40%显示设备信息和标签，右边60%显示日志
          Column() {
            Blank().height(TITLE_BAR_HEIGHT_MINI)
            
            Row() {
            
            // 左侧：设备信息和标签
            Column() {
              this.buildDeviceInfo()
              this.buildLogStats()
            }
            .width('40%')
            .height('100%')
            
            // 右侧：搜索、筛选、按钮和日志列表
            Column() {
              this.buildFilter()
              this.buildActionButtons()
              
              if (this.filteredLogs.length === 0) {
                Column({ space: 20 }) {
                  Text('暂无日志')
                    .fontSize(16)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                }
                .width('100%')
                .layoutWeight(1)
                .justifyContent(FlexAlign.Center)
              } else {
                Scroll(this.scroller) {
                  Column() {
                    ForEach(this.filteredLogs, (log: LogEntry) => {
                      this.buildLogItem(log)
                    }, (log: LogEntry) => `${log.id}`)
                  }
                  .width('100%')
                }
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
          // 竖屏布局：原有布局
          Column() {
            Blank().height(TITLE_BAR_HEIGHT_MINI)
            
            this.buildDeviceInfo()
            this.buildLogStats()
            this.buildFilter()
            this.buildActionButtons()

            if (this.filteredLogs.length === 0) {
            Column({ space: 20 }) {
              Text('暂无日志')
                .fontSize(16)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            Scroll(this.scroller) {
              Column() {
                ForEach(this.filteredLogs, (log: LogEntry) => {
                  this.buildLogItem(log)
                }, (log: LogEntry) => `${log.id}`)
              }
              .width('100%')
            }
              .layoutWeight(1)
              .edgeEffect(EdgeEffect.Spring)
              .scrollBar(BarState.Auto)
            }
          }
          .width('100%')
          .height('100%')
        }
      }
    }
    .titleBar({
      padding: {
        start: LengthMetrics.vp(16),
        end: LengthMetrics.vp(16)
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.COMMON_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(TITLE_BAR_HEIGHT_MINI)
        },
        originalStyle: {
          backgroundStyle: { backgroundColor: Color.Transparent },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: this.themeState.currentTheme === ThemeType.DARK ? '#E61A1A1A' : '#E6F5F5F5'
          },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        }
      },
      content: {
        title: { mainTitle: '日志管理' },
        menu: {
          value: [{
            content: {
              label: '切换主题',
              icon: $r('app.media.SculptureLargeAnimalistA'),
              isEnabled: true,
              action: () => { this.themeManager.toggleTheme(); }
            }
          }]
        }
      }
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.onPageShow();
      this.onReady();
    })
    .backgroundColor(Color.Transparent)
  }
}

export { LogManagerPage }
