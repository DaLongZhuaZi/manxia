// 文件路径：entry/src/main/ets/pages/SourceSettingsPage.ets
/**
 * 图源设置页面
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, UIContext } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { AnimatedComponent } from '../Framework/Animation/AnimatedComponent';
import { AnimationType } from '../Framework/Animation/GlobalAnimationSystem';
import { logger } from '../Utils/Logger';
import { DataManager, UserSettingsDatabaseRecord } from '../Framework/Data/DataManager';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener } from '../Framework/Managers/DeviceAdaptationManager';
import { WebViewSourceManager } from '../Framework/WebView/WebViewSourceManager';
import { WebViewAuthManager } from '../Framework/WebView/WebViewAuthManager';
import { ComicSourceDatabaseRecord } from '../Framework/Database/DatabaseTypes';
import CookieManager from '../Framework/Managers/CookieManager';
import { SourceLoginPageParams } from './SourceLoginPage';

const TAG: string = 'SourceSettingsPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

/**
 * 页面导航参数
 */
export interface SourceSettingsPageParams {
  sourceName: string;
}

@Component
export struct SourceSettingsPage {
  @State pathStack: NavPathStack = new NavPathStack();
  private uiContext: UIContext | undefined = undefined;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();

  private dataManager: DataManager = DataManager.getInstance();
  private webViewManager: WebViewSourceManager = WebViewSourceManager.getInstance();
  private authManager: WebViewAuthManager = WebViewAuthManager.getInstance();
  private scroller: Scroller = new Scroller();

  // 参数
  private pageParams: SourceSettingsPageParams | null = null;

  // 基本设置
  @State homeItemsPerPage: number = 20;
  @State readerPreloadCount: number = 10;
  @State preloadCurrentChapter: boolean = true;
  @State preloadNextChapter: boolean = false;
  @State downloadWhileReading: boolean = true;
  @State maxCacheSizeMB: number = 1024; // 以MB为单位

  // 登录设置
  @State username: string = '';
  @State password: string = '';
  @State cookieInput: string = '';
  @State cookieStatusText: string = '';
  @State isSaving: boolean = false;
  @State loginUrl: string = '';
  @State usernameSelector: string = '';
  @State passwordSelector: string = '';
  @State submitSelector: string = '';

  // 设备方向
  @State private isLandscape: boolean = false;
  private deviceOrientationListener: DeviceChangeListener | null = null;
  private deviceAdaptationManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();

  aboutToAppear(): void {
    logger.info(TAG, '=== aboutToAppear 开始 ===');
    const ui = this.getUIContext();
    this.uiContext = ui;
    ThemeAwareHelper.initializeThemeAware(
      TAG,
      this.themeState,
      (newTheme: ThemeType) => {},
      (newState: ThemeAwareState) => { this.themeState = newState; }
    );

    // 初始化设备方向
    const deviceInfo = this.deviceAdaptationManager.getDeviceInfo();
    this.isLandscape = deviceInfo.isLandscape;

    // 注册设备方向监听
    this.deviceOrientationListener = (deviceInfo: DeviceInfo) => {
      this.isLandscape = deviceInfo.isLandscape;
    };
    this.deviceAdaptationManager.addListener(this.deviceOrientationListener);

    logger.info(TAG, '=== aboutToAppear 结束 ===');
  }

  onPageShow() {
    logger.info(TAG, '=== onPageShow 开始 ===');
    logger.info(TAG, '=== onPageShow 结束 ===');
  }


  private async loadSettings(): Promise<void> {
    if (!this.pageParams || !this.pageParams.sourceName) {
      logger.error(TAG, '无效的sourceName，无法加载设置');
      this.showToast('页面参数错误');
      return;
    }
    
    try {
      const sourceName: string = this.pageParams.sourceName;
      logger.info(TAG, `开始加载图源设置: sourceName=${sourceName}`);
      
      // 获取图源记录以获取数字 ID（用于设置查询）
      const sourceRecord = await this.dataManager.getComicSourceByName(sourceName);
      if (!sourceRecord) {
        logger.error(TAG, `未找到图源记录: sourceName=${sourceName}`);
        return;
      }
      const sid: number = Number(sourceRecord.id);
      
      const s1: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'homeItemsPerPage');
      const s2: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'readerPreloadCount');
      const s3: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'preloadCurrentChapter');
      const s4: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'preloadNextChapter');
      const s5: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'downloadWhileReading');
      const s6: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'maxCacheSize');
      const creds = await this.dataManager.getSourceCredentials(sid);
      const l1: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'login.url');
      const l2: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'login.usernameSelector');
      const l3: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'login.passwordSelector');
      const l4: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'login.submitSelector');

      if (s1 && s1.settingValue) { this.homeItemsPerPage = Number(s1.settingValue); }
      if (s2 && s2.settingValue) { this.readerPreloadCount = Number(s2.settingValue); }
      if (s3 && s3.settingValue) { this.preloadCurrentChapter = s3.settingValue === '1'; }
      if (s4 && s4.settingValue) { this.preloadNextChapter = s4.settingValue === '1'; }
      if (s5 && s5.settingValue) { this.downloadWhileReading = s5.settingValue === '1'; }
      if (s6 && s6.settingValue) { this.maxCacheSizeMB = Math.round(Number(s6.settingValue) / (1024 * 1024)); }
      if (creds) { this.username = creds.username; this.password = creds.password; }
      if (l1 && l1.settingValue) { this.loginUrl = l1.settingValue; }
      if (l2 && l2.settingValue) { this.usernameSelector = l2.settingValue; }
      if (l3 && l3.settingValue) { this.passwordSelector = l3.settingValue; }
      if (l4 && l4.settingValue) { this.submitSelector = l4.settingValue; }
    } catch (error) {
      logger.error(TAG, '加载图源设置失败', String(error));
    }
    // 刷新 Cookie 状态
    try {
      const sourceName: string = this.pageParams.sourceName;
      const sourceRecord = await this.dataManager.getComicSourceByName(sourceName);
      if (sourceRecord) {
        const sid: number = Number(sourceRecord.id);
        const info = await CookieManager.getInstance().getCookieInfo(sid);
        if (info.hasCookie) {
          this.cookieStatusText = `已保存Cookie（${String(info.cookieCount)} 条）`;
        } else {
          this.cookieStatusText = '未保存Cookie';
        }
      }
    } catch (err) {
      logger.warn(TAG, '刷新Cookie状态失败', String(err));
      this.cookieStatusText = 'Cookie状态不可用';
    }
  }

  private async saveSettings(): Promise<void> {
    if (!this.pageParams || !this.pageParams.sourceName) {
      this.showToast('无效的图源');
      return;
    }
    
    this.isSaving = true;
    try {
      const sourceName: string = this.pageParams.sourceName;
      const sourceRecord = await this.dataManager.getComicSourceByName(sourceName);
      if (!sourceRecord) {
        this.showToast('未找到图源记录');
        this.isSaving = false;
        return;
      }
      const sid: number = Number(sourceRecord.id);
      
      await this.dataManager.saveSourceUserSetting(sid, 'homeItemsPerPage', String(this.homeItemsPerPage), 'number');
      await this.dataManager.saveSourceUserSetting(sid, 'readerPreloadCount', String(this.readerPreloadCount), 'number');
      await this.dataManager.saveSourceUserSetting(sid, 'preloadCurrentChapter', this.preloadCurrentChapter ? '1' : '0', 'boolean');
      await this.dataManager.saveSourceUserSetting(sid, 'preloadNextChapter', this.preloadNextChapter ? '1' : '0', 'boolean');
      await this.dataManager.saveSourceUserSetting(sid, 'downloadWhileReading', this.downloadWhileReading ? '1' : '0', 'boolean');
      await this.dataManager.saveSourceUserSetting(sid, 'maxCacheSize', String(this.maxCacheSizeMB * 1024 * 1024), 'number');
      await this.authManager.saveCredentials(sid, this.username, this.password);
      await this.dataManager.saveSourceUserSetting(sid, 'login.url', this.loginUrl, 'string');
      await this.dataManager.saveSourceUserSetting(sid, 'login.usernameSelector', this.usernameSelector, 'string');
      await this.dataManager.saveSourceUserSetting(sid, 'login.passwordSelector', this.passwordSelector, 'string');
      await this.dataManager.saveSourceUserSetting(sid, 'login.submitSelector', this.submitSelector, 'string');
      this.showToast('设置已保存');
    } catch (error) {
      logger.error(TAG, '保存图源设置失败', String(error));
      this.showToast('保存失败');
    }
    this.isSaving = false;
  }

  private async applyCookieInput(): Promise<void> {
    if (!this.pageParams || !this.pageParams.sourceName) {
      this.showToast('无效的图源');
      return;
    }
    
    const sourceName: string = this.pageParams.sourceName;
    const sourceRecord = await this.dataManager.getComicSourceByName(sourceName);
    if (!sourceRecord) {
      this.showToast('未找到图源记录');
      return;
    }
    const sid: number = Number(sourceRecord.id);
    
    const controller = this.webViewManager.getWebViewInstance(sourceName);
    await this.authManager.loginWithCookieString(sid, controller, this.cookieInput);
    this.showToast('Cookie已保存并应用');
    // 应用后刷新状态
    try {
      const info2 = await CookieManager.getInstance().getCookieInfo(sid);
      this.cookieStatusText = info2.hasCookie ? `已保存Cookie（${String(info2.cookieCount)} 条）` : '未保存Cookie';
    } catch (_e) {}
  }

  private async fetchCookieWithoutLogin(): Promise<void> {
    if (!this.pageParams || !this.pageParams.sourceName) {
      this.showToast('无效的图源');
      return;
    }
    
    try {
      const sourceName: string = this.pageParams.sourceName;
      logger.info(TAG, `获取Cookie: sourceName=${sourceName}`);
      const srcRecord: ComicSourceDatabaseRecord | null = await this.dataManager.getComicSourceByName(sourceName);
      
      // 如果数据库中没有记录，尝试从配置文件获取baseUrl
      let baseUrl: string = '';
      if (!srcRecord) {
        logger.info(TAG, '未找到图源记录，尝试从DataManager获取配置');
        // 尝试从DataManager获取源配置
        try {
          const sourceConfig: ESObject | null = await this.dataManager.getSourceConfigByPkg(sourceName);
          if (sourceConfig) {
            const configObj = sourceConfig as Record<string, Object>;
            const keys = Object.keys(configObj);
            
            // 尝试从metadata.baseUrl获取
            if (keys.includes('metadata')) {
              const metadata = configObj['metadata'] as Record<string, Object>;
              const metaKeys = Object.keys(metadata);
              if (metaKeys.includes('baseUrl')) {
                baseUrl = String(metadata['baseUrl']);
              }
            }
            
            // 如果metadata中没有，尝试直接从配置根获取
            if (baseUrl.length === 0 && keys.includes('baseUrl')) {
              baseUrl = String(configObj['baseUrl']);
            }
          }
        } catch (e) {
          logger.warn(TAG, `获取源配置失败: ${String(e)}`);
        }
        
        if (baseUrl.length === 0) {
          this.showToast('未找到图源配置');
          return;
        }
      } else {
        baseUrl = srcRecord.baseUrl;
      }
      
      if (baseUrl.length === 0) { this.showToast('图源基础URL为空'); return; }
      if (!srcRecord) { this.showToast('未找到图源记录'); return; }
      
      const sid: number = Number(srcRecord.id);
      const ok: boolean = await CookieManager.getInstance().fetchCookiesByDefaultRequest(sid, baseUrl);
      if (ok) {
        this.showToast('已获取并保存服务器Cookie');
        const info = await CookieManager.getInstance().getCookieInfo(sid);
        this.cookieStatusText = info.hasCookie ? `已保存Cookie（${String(info.cookieCount)} 条）` : '未保存Cookie';
      } else {
        this.showToast('未获取到服务器Cookie');
      }
    } catch (error) {
      logger.error(TAG, '获取服务器Cookie失败', String(error));
      this.showToast('获取Cookie失败');
    }
  }

  private async openLoginPage(): Promise<void> {
    if (!this.pageParams || !this.pageParams.sourceName) {
      this.showToast('无效的图源');
      return;
    }
    
    const sourceName: string = this.pageParams.sourceName;
    const sourceRecord = await this.dataManager.getComicSourceByName(sourceName);
    if (!sourceRecord) {
      this.showToast('未找到图源记录');
      return;
    }
    const baseUrl = String(sourceRecord.baseUrl);
    const url: string = this.loginUrl && this.loginUrl.length > 0 ? this.loginUrl : (baseUrl + '/login');
    
    // 跳转到独立的登录页面
    const loginParams: SourceLoginPageParams = {
      sourceName: sourceName,
      loginUrl: url,
      loginType: 'webview'
    };
    this.pathStack.pushPathByName('SourceLoginPage', loginParams);
    logger.info(TAG, `跳转到登录页面: sourceName=${sourceName}, url=${url}`);
  }

  private async performFormLogin(): Promise<void> {
    if (!this.pageParams || !this.pageParams.sourceName) {
      this.showToast('无效的图源');
      return;
    }
    
    const sourceName: string = this.pageParams.sourceName;
    const sourceRecord = await this.dataManager.getComicSourceByName(sourceName);
    if (!sourceRecord) {
      this.showToast('未找到图源记录');
      return;
    }
    const baseUrl = String(sourceRecord.baseUrl);
    const url: string = this.loginUrl && this.loginUrl.length > 0 ? this.loginUrl : (baseUrl + '/login');
    
    // 跳转到独立的登录页面（表单模式）
    const loginParams: SourceLoginPageParams = {
      sourceName: sourceName,
      loginUrl: url,
      loginType: 'form',
      username: this.username,
      password: this.password,
      usernameSelector: this.usernameSelector,
      passwordSelector: this.passwordSelector,
      submitSelector: this.submitSelector
    };
    this.pathStack.pushPathByName('SourceLoginPage', loginParams);
    logger.info(TAG, `跳转到表单登录页面: sourceName=${sourceName}`);
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 2000,
        bottom: 100
      });
    } catch (e) {
      logger.warn(TAG, '显示Toast失败', String(e));
    }
    logger.info(TAG, message);
  }

  build() {
    HdsNavDestination() {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Scroll(this.scroller) {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            // 基础设置分组
            Column() {
              Text('基础')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .margin({ bottom: 12 })

              // 首页每页条目数
              Column() {
                Row() {
                  Text('首页每页条目数')
                    .fontSize(14)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  Text('?')
                    .fontSize(12)
                    .fontColor(Color.Gray)
                    .width(16)
                    .height(16)
                    .textAlign(TextAlign.Center)
                    .borderRadius(8)
                    .border({ width: 1, color: Color.Gray })
                    .margin({ left: 4 })
                    .bindPopup(this.homeItemsPerPage >= 0, {
                      message: '控制图源首页每次加载的漫画数量，范围10-100。数值越大加载越慢，但减少翻页次数',
                      placement: Placement.Top,
                      enableArrow: true,
                      showInSubWindow: false,
                      mask: true,
                      autoCancel: true
                    })
                  Blank()
                  Text(`${this.homeItemsPerPage} 条`)
                    .fontSize(14)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                }
                .width('100%')
                
                Slider({
                  value: this.homeItemsPerPage,
                  min: 10,
                  max: 100,
                  step: 5,
                  style: SliderStyle.InSet
                })
                .width('100%')
                .trackThickness(4)
                .onChange((value: number) => {
                  this.homeItemsPerPage = Math.round(value);
                })
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })

              // 阅读器预加载数量
              Column() {
                Row() {
                  Text('阅读器预加载数量')
                    .fontSize(14)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  Text('?')
                    .fontSize(12)
                    .fontColor(Color.Gray)
                    .width(16)
                    .height(16)
                    .textAlign(TextAlign.Center)
                    .borderRadius(8)
                    .border({ width: 1, color: Color.Gray })
                    .margin({ left: 4 })
                    .bindPopup(this.readerPreloadCount >= 0, {
                      message: '阅读时提前加载的图片页数，范围1-10。数值越大翻页越流畅，但占用更多内存',
                      placement: Placement.Top,
                      enableArrow: true,
                      showInSubWindow: false,
                      mask: true,
                      autoCancel: true
                    })
                  Blank()
                  Text(`${this.readerPreloadCount} 页`)
                    .fontSize(14)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                }
                .width('100%')
                
                Slider({
                  value: this.readerPreloadCount,
                  min: 0,
                  max: 50,
                  step: 1,
                  style: SliderStyle.InSet
                })
                .width('100%')
                .trackThickness(4)
                .onChange((value: number) => {
                  this.readerPreloadCount = Math.round(value);
                })
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })

              // 预加载当前章节
              Row() {
                Row() {
                  Text('预加载当前章节')
                    .fontSize(14)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  Text('?')
                    .fontSize(12)
                    .fontColor(Color.Gray)
                    .width(16)
                    .height(16)
                    .textAlign(TextAlign.Center)
                    .borderRadius(8)
                    .border({ width: 1, color: Color.Gray })
                    .margin({ left: 4 })
                    .bindPopup(this.preloadCurrentChapter || !this.preloadCurrentChapter, {
                      message: '打开章节时自动预加载所有图片，提升阅读体验但消耗流量',
                      placement: Placement.Top,
                      enableArrow: true,
                      showInSubWindow: false,
                      mask: true,
                      autoCancel: true
                    })
                }
                .layoutWeight(1)
                
                Toggle({ type: ToggleType.Switch, isOn: this.preloadCurrentChapter })
                  .onChange((isOn: boolean) => { this.preloadCurrentChapter = isOn; })
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })

              // 预加载下一章节
              Row() {
                Row() {
                  Text('预加载下一章节')
                    .fontSize(14)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  Text('?')
                    .fontSize(12)
                    .fontColor(Color.Gray)
                    .width(16)
                    .height(16)
                    .textAlign(TextAlign.Center)
                    .borderRadius(8)
                    .border({ width: 1, color: Color.Gray })
                    .margin({ left: 4 })
                    .bindPopup(this.preloadNextChapter || !this.preloadNextChapter, {
                      message: '阅读到最后几页时自动预加载下一章节，无缝连续阅读',
                      placement: Placement.Top,
                      enableArrow: true,
                      showInSubWindow: false,
                      mask: true,
                      autoCancel: true  
                    })
                }
                .layoutWeight(1)
                
                Toggle({ type: ToggleType.Switch, isOn: this.preloadNextChapter })
                  .onChange((isOn: boolean) => { this.preloadNextChapter = isOn; })
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })

              // 边看边下载
              Row() {
                Row() {
                  Text('边看边下载')
                    .fontSize(14)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  Text('?')
                    .fontSize(12)
                    .fontColor(Color.Gray)
                    .width(16)
                    .height(16)
                    .textAlign(TextAlign.Center)
                    .borderRadius(8)
                    .border({ width: 1, color: Color.Gray })
                    .margin({ left: 4 })
                    .bindPopup(this.downloadWhileReading || !this.downloadWhileReading, {
                      message: '开启后，阅读时自动下载图片到永久存储，不会被清理。关闭后使用临时缓存，受最大缓存限制',
                      placement: Placement.Top,
                      enableArrow: true,
                      showInSubWindow: false,
                      mask: true,
                      autoCancel: true
                    })
                }
                .layoutWeight(1)
                
                Toggle({ type: ToggleType.Switch, isOn: this.downloadWhileReading })
                  .onChange((isOn: boolean) => { this.downloadWhileReading = isOn; })
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })

              // 最大缓存大小（仅在未开启边看边下载时有效）
              if (!this.downloadWhileReading) {
                Column() {
                  Row() {
                    Text('最大缓存大小')
                      .fontSize(14)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    Text('?')
                      .fontSize(12)
                      .fontColor(Color.Gray)
                      .width(16)
                      .height(16)
                      .textAlign(TextAlign.Center)
                      .borderRadius(8)
                      .border({ width: 1, color: Color.Gray })
                      .margin({ left: 4 })
                      .bindPopup(true, {
                        message: '临时缓存的最大大小，超出后自动清理最旧的缓存',
                        placement: Placement.Top,
                        enableArrow: true,
                        showInSubWindow: false,
                        mask: true,
                        autoCancel: true
                      })
                    Blank()
                    Text(`${this.maxCacheSizeMB} MB`)
                      .fontSize(14)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  }
                  .width('100%')
                  
                  Slider({
                    value: this.maxCacheSizeMB,
                    min: 100,
                    max: 10240,
                    step: 100,
                    style: SliderStyle.InSet
                  })
                  .width('100%')
                  .trackThickness(4)
                  .onChange((value: number) => {
                    this.maxCacheSizeMB = Math.round(value);
                  })
                }
                .width('100%')
                .padding({ top: 8, bottom: 8 })
              }
            }
            .width(this.isLandscape ? '48%' : '100%')
            .padding(16)
            .margin({ bottom: 16 })
            .borderRadius(12)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_primary', this.themeState.currentTheme))

            // 登录设置分组
            Column() {
              Text('登录')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .margin({ bottom: 12 })

              // 账号
              Column() {
                Text('账号')
                  .fontSize(14)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .margin({ bottom: 4 })
                TextInput({ text: this.username })
                  .width('100%')
                  .onChange((v: string) => { this.username = v; })
              }
              .width('100%')
              .margin({ bottom: 12 })

              // 密码
              Column() {
                Text('密码')
                  .fontSize(14)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .margin({ bottom: 4 })
                TextInput({ text: this.password })
                  .width('100%')
                  .type(InputType.Password)
                  .onChange((v: string) => { this.password = v; })
              }
              .width('100%')
              .margin({ bottom: 12 })

              // 登录页地址
              Column() {
                Text('登录页地址')
                  .fontSize(14)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .margin({ bottom: 4 })
                TextInput({ text: this.loginUrl })
                  .width('100%')
                  .onChange((v: string) => { this.loginUrl = v; })
              }
              .width('100%')
              .margin({ bottom: 12 })

              // 账号选择器
              Column() {
                Text('账号选择器')
                  .fontSize(14)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .margin({ bottom: 4 })
                TextInput({ text: this.usernameSelector })
                  .width('100%')
                  .onChange((v: string) => { this.usernameSelector = v; })
              }
              .width('100%')
              .margin({ bottom: 12 })

              // 密码选择器
              Column() {
                Text('密码选择器')
                  .fontSize(14)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .margin({ bottom: 4 })
                TextInput({ text: this.passwordSelector })
                  .width('100%')
                  .onChange((v: string) => { this.passwordSelector = v; })
              }
              .width('100%')
              .margin({ bottom: 12 })

              // 提交按钮选择器
              Column() {
                Text('提交按钮选择器')
                  .fontSize(14)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .margin({ bottom: 4 })
                TextInput({ text: this.submitSelector })
                  .width('100%')
                  .onChange((v: string) => { this.submitSelector = v; })
              }
              .width('100%')
              .margin({ bottom: 12 })

              // Cookie
              Column() {
                Text('Cookie（name=value; ...）')
                  .fontSize(14)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .margin({ bottom: 4 })
                Row() {
                  Text(this.cookieStatusText)
                    .fontSize(12)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  Button('获取Cookie（无Cookie请求）')
                    .layoutWeight(1)
                    .margin({ left: 8 })
                    .onClick(() => { this.fetchCookieWithoutLogin(); })
                }
                .width('100%')
                .margin({ bottom: 6 })
                TextInput({ text: this.cookieInput })
                  .width('100%')
                  .onChange((v: string) => { this.cookieInput = v; })
              }
              .width('100%')
              .margin({ bottom: 16 })

              // 操作按钮
              Row() {
                Button('保存设置')
                  .layoutWeight(1)
                  .margin({ right: 8 })
                  .onClick(() => { this.saveSettings(); })
                Button('应用Cookie')
                  .layoutWeight(1)
                  .margin({ left: 4, right: 4 })
                  .onClick(() => { this.applyCookieInput(); })
              }
              .width('100%')
              .margin({ bottom: 8 })

              Row() {
                Button('打开登录页')
                  .layoutWeight(1)
                  .margin({ right: 8 })
                  .onClick(() => { this.openLoginPage(); })
                Button('表单登录')
                  .layoutWeight(1)
                  .margin({ left: 4 })
                  .onClick(() => { this.performFormLogin(); })
              }
              .width('100%')
            }
            .width(this.isLandscape ? '48%' : '100%')
            .padding(16)
            .borderRadius(12)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_primary', this.themeState.currentTheme))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: this.statusBarHeight + 8, bottom: this.navigationBarHeight + 8 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
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
        title: { mainTitle: '图源设置' }
      }
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      // 从context直接获取参数
      logger.info(TAG, `onReady被调用, pathInfo.param类型: ${typeof context.pathInfo.param}`);
      logger.info(TAG, `onReady pathInfo.param内容: ${JSON.stringify(context.pathInfo.param)}`);
      const params = context.pathInfo.param as SourceSettingsPageParams;
      logger.info(TAG, `转换后的params: ${JSON.stringify(params)}`);
      if (params && params.sourceName) {
        logger.info(TAG, `onReady获取到参数: sourceName=${params.sourceName}`);
        this.pageParams = params;
        this.loadSettings();
      } else {
        logger.error(TAG, `onReady未获取到有效参数, params=${JSON.stringify(params)}`);
      }
    })
    .backgroundColor(Color.Transparent)
  }
}
