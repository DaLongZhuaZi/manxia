/**
 * 小说书源登录页面
 * 支持两种登录方式：
 * 1. loginUi - 表单登录
 * 2. loginUrl - WebView登录
 * 使用 HdsNavDestination 实现统一的导航体验
 * 
 * 文件路径: entry/src/main/ets/pages/NovelSourceLoginPage.ets
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { logger } from '../Utils/Logger';
import { webview } from '@kit.ArkWeb';
import { getNovelSourceManager } from '../Framework/Novel/NovelSourceManager';
import { getNovelLoginManager, LoginUiItem, LoginUiItemStyle } from '../Framework/Novel/NovelLoginManager';
import { getLegadoRhinoEngine } from '../Framework/Novel/LegadoRhinoEngine';
import { LegadoBookSource } from '../Framework/Novel/LegadoSourceTypes';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';

const TAG = 'NovelSourceLoginPage';

export interface NovelSourceLoginPageParams {
  sourceId: string;
}

const TITLE_BAR_HEIGHT_MINI = 56;

@Component
export struct NovelSourceLoginPage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = `NovelSourceLoginPage_${Date.now()}`;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  
  @State source: LegadoBookSource | null = null;
  @State loginUiItems: LoginUiItem[] = [];
  @State formData: Record<string, string> = {};
  @State isLoading: boolean = false;
  @State loadingAction: string = ''; // 当前正在执行的操作
  @State useWebView: boolean = false;
  @State webViewUrl: string = '';
  @State webViewTitle: string = '';
  @State webViewLoading: boolean = true;
  private sourceId: string = '';
  private sourceManager = getNovelSourceManager();
  private loginManager = getNovelLoginManager();
  private webViewController: webview.WebviewController = new webview.WebviewController();
  // Rhino沙箱专用的WebView控制器（独立于LegadoJsEngine的WebView）
  private rhinoWebViewController: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }

  async loadSource(): Promise<void> {
    if (!this.sourceId) return;
    
    // 确保NovelLoginManager已初始化
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await this.loginManager.initialize(context);
    } catch (error) {
      logger.warn(TAG, `初始化登录管理器失败: ${String(error)}`);
    }
    
    this.source = this.sourceManager.getSource(this.sourceId) || null;
    if (this.source) {
      // 判断登录方式
      // 优先级：
      // 1. 如果有loginUi配置，使用动态表单（无论loginUrl是什么）
      // 2. 如果loginUrl是普通URL（非JS代码），使用WebView
      // 3. 如果loginUrl是JS代码但没有loginUi，使用默认表单
      
      if (this.source.loginUi) {
        // 有loginUi配置 - 使用动态表单
        this.useWebView = false;
        this.loginUiItems = this.loginManager.getLoginUi(this.source);
        logger.info(TAG, `使用动态表单登录，共${this.loginUiItems.length}个UI项`);
        
        // 加载之前保存的表单数据
        const savedFormData = this.loginManager.getLoginFormData(this.sourceId);
        
        // 初始化表单数据：优先使用保存的数据，否则使用默认值
        this.loginUiItems.forEach((item: LoginUiItem) => {
          if (item.type !== 'button') {
            this.formData[item.name] = savedFormData[item.name] || item.value || '';
          }
        });
      } else if (this.source.loginUrl) {
        const isJsCode = this.source.loginUrl.startsWith('@js:') || 
                         this.source.loginUrl.startsWith('<js>') ||
                         this.source.loginUrl.includes('function ') ||
                         this.source.loginUrl.includes('const ') ||
                         this.source.loginUrl.includes('let ') ||
                         this.source.loginUrl.includes('var ');
        
        if (!isJsCode && (this.source.loginUrl.startsWith('http://') || this.source.loginUrl.startsWith('https://'))) {
          // 普通URL - 使用WebView
          this.useWebView = true;
          this.webViewUrl = this.getFullLoginUrl(this.source.loginUrl, this.source.bookSourceUrl);
          logger.info(TAG, `使用WebView登录: ${this.webViewUrl}`);
        } else {
          // JS代码但没有loginUi - 使用默认表单
          this.useWebView = false;
          this.loginUiItems = this.loginManager.getLoginUi(this.source);
          logger.info(TAG, `使用默认表单登录（JS登录）`);
          
          // 加载之前保存的表单数据
          const savedFormData = this.loginManager.getLoginFormData(this.sourceId);
          
          this.loginUiItems.forEach((item: LoginUiItem) => {
            if (item.type !== 'button') {
              this.formData[item.name] = savedFormData[item.name] || item.value || '';
            }
          });
        }
      }
    }
  }

  /**
   * 更新表单字段并保存
   */
  async updateFormField(name: string, value: string): Promise<void> {
    this.formData[name] = value;
    // 保存表单数据到持久化存储
    if (this.sourceId) {
      await this.loginManager.saveLoginFormData(this.sourceId, this.formData);
    }
  }

  getFullLoginUrl(loginUrl: string, baseUrl: string): string {
    if (loginUrl.startsWith('http://') || loginUrl.startsWith('https://')) {
      return loginUrl;
    }
    // 相对路径，拼接baseUrl
    const base = baseUrl.endsWith('/') ? baseUrl.slice(0, -1) : baseUrl;
    const path = loginUrl.startsWith('/') ? loginUrl : '/' + loginUrl;
    return base + path;
  }

  async doLogin(): Promise<void> {
    if (!this.source) return;
    
    this.isLoading = true;
    try {
      const result = await this.loginManager.login(this.source, this.formData);
      
      if (result.success) {
        promptAction.showToast({ message: result.message || '登录成功' });
        this.pathStack.pop();
      } else {
        promptAction.showToast({ message: result.message || '登录失败' });
      }
    } catch (error) {
      logger.error(TAG, `登录失败: ${String(error)}`);
      promptAction.showToast({ message: '登录失败: ' + String(error) });
    }
    this.isLoading = false;
  }

  /**
   * 保存表单数据（不执行登录，仅保存）
   */
  async saveFormData(): Promise<void> {
    if (!this.source) return;
    
    try {
      // 保存登录信息到持久化存储
      this.loginManager.putLoginInfo(this.source.bookSourceUrl, JSON.stringify(this.formData));
      await this.loginManager.savePersistedData();
      
      promptAction.showToast({ message: '保存成功' });
      logger.info(TAG, `保存表单数据: ${this.source.bookSourceName}`);
    } catch (error) {
      logger.error(TAG, `保存失败: ${String(error)}`);
      promptAction.showToast({ message: '保存失败: ' + String(error) });
    }
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 背景层：扩展到系统栏区域，实现完全沉浸式背景
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .animation(ThemeAwareHelper.getThemeTransitionAnimation())
        
        // 隐藏的WebView用于LegadoJsEngine的降级执行（网络请求等）
        // 使用本地HTML页面而不是about:blank，避免跨域限制
        Web({ src: $rawfile('js_executor.html'), controller: this.webViewController })
          .width(1)
          .height(1)
          .opacity(0)
          .position({ x: -100, y: -100 })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .fileAccess(true)
          .mixedMode(MixedMode.All)
          .onControllerAttached(() => {
            // WebView控制器已附加，设置到LegadoJsEngine
            const rhinoEngine = getLegadoRhinoEngine();
            rhinoEngine.setWebviewController(this.webViewController);
            logger.info(TAG, 'WebView控制器已设置到LegadoJsEngine');
          })
        
        // Rhino沙箱专用的WebView（独立实例，用于运行沙箱脚本）
        // 使用本地HTML页面而不是about:blank，避免跨域限制
        Web({ src: $rawfile('js_executor.html'), controller: this.rhinoWebViewController })
          .width(1)
          .height(1)
          .opacity(0)
          .position({ x: -200, y: -200 })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .fileAccess(true)
          .mixedMode(MixedMode.All)
          .onControllerAttached(() => {
            // Rhino沙箱WebView控制器已附加
            const rhinoEngine = getLegadoRhinoEngine();
            rhinoEngine.setRhinoWebviewController(this.rhinoWebViewController);
            logger.info(TAG, 'Rhino沙箱WebView控制器已设置');
          })
        
        // 内容层：预留标题栏高度
        Column() {
          
          if (!this.source) {
            this.buildError()
          } else if (this.useWebView) {
            this.buildWebViewLogin()
          } else {
            this.buildLoginForm()
          }
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.statusBarHeight, bottom: this.navigationBarHeight })
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({
      padding: {
        start: LengthMetrics.vp(16),
        end: LengthMetrics.vp(16)
      },
      style: {
        originalStyle: {
          backgroundStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme) },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        }
      },
      content: {
        title: {
          mainTitle: this.useWebView ? (this.webViewTitle || '登录') : '书源登录'
        },
        menu: this.useWebView ? {
          value: [{
            content: {
              label: '刷新',
              icon: $r('app.media.ic_refresh'),
              isEnabled: true,
              action: () => {
                this.webViewController.refresh();
              }
            }
          }, {
            content: {
              label: '完成登录',
              icon: $r('app.media.ic_check'),
              isEnabled: true,
              action: () => this.onWebViewLoginComplete()
            }
          }]
        } : {
          value: [{
            content: {
              label: '保存',
              icon: $r('app.media.ic_check'),
              isEnabled: !this.isLoading,
              action: () => this.saveFormData()
            }
          }]
        }
      }
    })
    .backgroundColor(Color.Transparent)
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as NovelSourceLoginPageParams | null;
      if (param?.sourceId) {
        this.sourceId = param.sourceId;
        this.loadSource();
      }
    })
  }

  @Builder
  buildTopBar() {
    Row() {
      Image($r('app.media.ic_back'))
        .width(24)
        .height(24)
        .margin({ left: 16 })
        .fillColor(ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme))
        .onClick(() => this.onBackPressed())
      
      Text(this.useWebView ? (this.webViewTitle || '登录') : '书源登录')
        .fontSize(18)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .margin({ left: 16 })
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      
      if (this.useWebView) {
        // 刷新按钮
        Image($r('app.media.ic_refresh'))
          .width(24)
          .height(24)
          .margin({ right: 8 })
          .fillColor(ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme))
          .onClick(() => {
            this.webViewController.refresh();
          })
        
        // 完成按钮
        Text('完成')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .margin({ right: 16 })
          .onClick(() => this.onWebViewLoginComplete())
      } else {
        Blank()
      }
    }
    .width('100%')
    .height(56)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
  }

  onBackPressed(): void {
    if (this.useWebView) {
      try {
        if (this.webViewController.accessBackward()) {
          this.webViewController.backward();
          return;
        }
      } catch (e) {
        // ignore
      }
    }
    this.pathStack.pop();
  }

  async onWebViewLoginComplete(): Promise<void> {
    if (!this.source) return;
    
    try {
      // 获取WebView中的Cookie
      const cookieManager = webview.WebCookieManager;
      const cookies = cookieManager.fetchCookieSync(this.webViewUrl);
      
      logger.info(TAG, `获取到Cookie: ${cookies}`);
      
      if (cookies) {
        // 解析Cookie字符串
        const cookieMap: Record<string, string> = {};
        const cookieParts = cookies.split(';');
        for (let i = 0; i < cookieParts.length; i++) {
          const part = cookieParts[i].trim();
          const eqIndex = part.indexOf('=');
          if (eqIndex > 0) {
            const key = part.substring(0, eqIndex).trim();
            const value = part.substring(eqIndex + 1).trim();
            cookieMap[key] = value;
          }
        }
        
        // 保存Cookie到登录管理器
        this.loginManager.setCookies(this.source.bookSourceUrl, cookieMap);
        this.loginManager.setLoggedIn(this.source.bookSourceUrl, true, cookieMap);
        
        promptAction.showToast({ message: '登录成功' });
        this.pathStack.pop();
      } else {
        promptAction.showToast({ message: '未检测到登录信息，请先登录' });
      }
    } catch (error) {
      logger.error(TAG, `获取Cookie失败: ${String(error)}`);
      promptAction.showToast({ message: '获取登录信息失败' });
    }
  }

  @Builder
  buildWebViewLogin() {
    Stack() {
      Web({ src: this.webViewUrl, controller: this.webViewController })
        .width('100%')
        .layoutWeight(1)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        .mixedMode(MixedMode.All)
        .cacheMode(CacheMode.Default)
        .onTitleReceive((event) => {
          if (event) {
            this.webViewTitle = event.title;
          }
        })
        .onPageBegin(() => {
          this.webViewLoading = true;
        })
        .onPageEnd(() => {
          this.webViewLoading = false;
        })
        .onErrorReceive((event) => {
          logger.error(TAG, `WebView错误: ${event?.error?.getErrorInfo()}`);
        })
      
      if (this.webViewLoading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(255,255,255,0.8)')
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  buildError() {
    Column() {
      Text('书源不存在')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildLoginForm() {
    Scroll() {
      Column() {
        // 书源信息头部
        Column() {
          Text(this.source?.bookSourceName || '')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Text(this.source?.bookSourceUrl || '')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .margin({ top: 4 })
        }
        .width('100%')
        .padding(20)
        .alignItems(HorizontalAlign.Center)
        
        // 输入字段区域
        Column() {
          ForEach(this.loginUiItems.filter((item: LoginUiItem) => item.type !== 'button'), (item: LoginUiItem) => {
            if (item.type === 'text') {
              this.buildTextInput(item)
            } else if (item.type === 'password') {
              this.buildPasswordInput(item)
            }
          })
        }
        .width('100%')
        .padding({ left: 20, right: 20 })
        
        // 按钮区域 - 使用Flex布局支持多按钮排列
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(this.loginUiItems.filter((item: LoginUiItem) => item.type === 'button'), (item: LoginUiItem) => {
            this.buildButton(item)
          })
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 20 })
      }
      .width('100%')
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder
  buildTextInput(item: LoginUiItem) {
    Column() {
      Text(item.hint || item.name)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .margin({ bottom: 8 })
      
      TextInput({ placeholder: item.hint || item.name, text: this.formData[item.name] })
        .width('100%')
        .height(48)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(8)
        .padding({ left: 16, right: 16 })
        .onChange((value: string) => {
          this.updateFormField(item.name, value);
        })
    }
    .width('100%')
    .margin({ bottom: 16 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildPasswordInput(item: LoginUiItem) {
    Column() {
      Text(item.hint || item.name)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .margin({ bottom: 8 })
      
      TextInput({ placeholder: item.hint || item.name, text: this.formData[item.name] })
        .type(InputType.Password)
        .width('100%')
        .height(48)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(8)
        .padding({ left: 16, right: 16 })
        .onChange((value: string) => {
          this.updateFormField(item.name, value);
        })
    }
    .width('100%')
    .margin({ bottom: 16 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildButton(item: LoginUiItem) {
    Button(this.isLoading && this.loadingAction === item.action ? '执行中...' : (item.name || item.hint || '按钮'))
      .width(item.style?.flexBasisPercent ? `${Math.floor(item.style.flexBasisPercent * 100 - 2)}%` : '100%')
      .height(44)
      .fontSize(14)
      .fontColor('#FFFFFF')
      .fontFamily(this.appFontFamily)
      .backgroundColor(this.isLoading ? 
        ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme) :
        ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      .borderRadius(8)
      .margin({ top: 8, bottom: 8 })
      .enabled(!this.isLoading)
      .onClick(() => this.executeButtonAction(item))
  }

  /**
   * 执行按钮操作
   */
  async executeButtonAction(item: LoginUiItem): Promise<void> {
    if (!this.source) return;
    
    const action = item.action;
    if (!action) {
      // 没有action，执行默认登录
      await this.doLogin();
      return;
    }
    
    this.isLoading = true;
    this.loadingAction = action;
    
    try {
      logger.info(TAG, `执行按钮操作: ${action}`);
      
      const result = await this.loginManager.executeButtonAction(this.source, action, this.formData);
      
      if (result.success) {
        promptAction.showToast({ message: result.message || '操作成功' });
      } else {
        promptAction.showToast({ message: result.message || '操作失败' });
      }
    } catch (error) {
      logger.error(TAG, `执行按钮操作失败: ${String(error)}`);
      promptAction.showToast({ message: '操作失败: ' + String(error) });
    }
    
    this.isLoading = false;
    this.loadingAction = '';
  }
}
