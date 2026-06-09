import { UIContext } from '@ohos.arkui.UIContext';
import { SafeUtils } from '../../Utils/SafeUtils';
/**
 * 小说书源登录管理器
 * 处理书源的登录逻辑、Cookie管理
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/NovelLoginManager.ets
 */

import { logger } from '../../Utils/Logger';
import { LegadoBookSource, LegadoLoginUiItem } from './LegadoSourceTypes';
import { getLegadoRhinoEngine } from './LegadoRhinoEngine';
import { ToastMessage, CookieChange, JsContext } from './LegadoJsEngine';
import { getCookieStore } from './LegadoCookieStore';
import { preferences } from '@kit.ArkData';
import { promptAction } from '@kit.ArkUI';

const TAG = 'NovelLoginManager';

/**
 * 登录UI项样式
 */
export interface LoginUiItemStyle {
  flexGrow?: number;
  flexBasisPercent?: number;
}

/**
 * 登录UI项
 */
export interface LoginUiItem {
  type: 'text' | 'password' | 'button' | 'checkbox' | 'spinner';
  name: string;
  hint?: string;
  value?: string;
  /** 按钮点击时执行的JS函数名 */
  action?: string;
  /** 样式配置 */
  style?: LoginUiItemStyle;
}

/**
 * 登录结果
 */
export interface LoginResult {
  success: boolean;
  message?: string;
  cookies?: Record<string, string>;
}

/**
 * 书源登录状态
 */
export interface SourceLoginStatus {
  sourceId: string;
  isLoggedIn: boolean;
  lastLoginTime?: number;
  cookies?: Record<string, string>;
}

// 持久化存储的key
const LOGIN_STATUS_STORAGE_KEY = 'novel_login_status';
const LOGIN_INFO_STORAGE_KEY = 'novel_login_info';
const LOGIN_HEADER_STORAGE_KEY = 'novel_login_header';
const SOURCE_VARIABLE_STORAGE_KEY = 'novel_source_variable';
const SOURCE_DATA_STORAGE_KEY = 'novel_source_data';
const LOGIN_FORM_DATA_STORAGE_KEY = 'novel_login_form_data';

/**
 * 小说书源登录管理器
 */
export class NovelLoginManager {
  private static instance: NovelLoginManager | null = null;
  private loginStatus: Map<string, SourceLoginStatus> = new Map();
  private cookies: Map<string, Record<string, string>> = new Map();
  private dataPreferences: preferences.Preferences | null = null;
  private initialized: boolean = false;
  
  // 登录信息存储（兼容Legado原版）
  private loginInfoStore: Map<string, string> = new Map();
  private loginHeaderStore: Map<string, string> = new Map();
  private sourceVariableStore: Map<string, string> = new Map();
  private sourceDataStore: Map<string, string> = new Map();
  // 登录表单数据存储（用于记住用户输入的账号密码等）
  private loginFormDataStore: Map<string, Record<string, string>> = new Map();

  private constructor() {}

  static getInstance(): NovelLoginManager {
    if (!NovelLoginManager.instance) {
      NovelLoginManager.instance = new NovelLoginManager();
    }
    return NovelLoginManager.instance;
  }

  /**
   * 初始化登录管理器，加载持久化的Cookie
   */
  async initialize(context: Context): Promise<void> {
    if (this.initialized) {
      return;
    }

    try {
      this.dataPreferences = await preferences.getPreferences(context, 'novel_login_data');
      await this.loadPersistedData();
      this.initialized = true;
      logger.info(TAG, 'NovelLoginManager 初始化完成');
    } catch (error) {
      logger.error(TAG, `初始化失败: ${String(error)}`);
    }
  }

  /**
   * 加载持久化的数据
   */
  private async loadPersistedData(): Promise<void> {
    if (!this.dataPreferences) return;

    try {
      // 加载登录状态
      const statusJson = await this.dataPreferences.get(LOGIN_STATUS_STORAGE_KEY, '') as string;
      logger.debug(TAG, `加载持久化数据: statusJson长度=${statusJson ? statusJson.length : 0}`);
      if (statusJson) {
        const statusArray = SafeUtils.parseArr(statusJson) as SourceLoginStatus[];
        statusArray.forEach((status: SourceLoginStatus) => {
          this.loginStatus.set(status.sourceId, status);
          if (status.cookies) {
            this.cookies.set(status.sourceId, status.cookies);
            logger.debug(TAG, `加载Cookie: sourceId=${status.sourceId}, cookieKeys=${Object.keys(status.cookies).join(',')}`);
          }
        });
        logger.info(TAG, `加载了 ${statusArray.length} 个书源的登录状态`);
      } else {
        logger.info(TAG, '没有持久化的登录状态数据');
      }
      
      // 加载登录信息
      const loginInfoJson = await this.dataPreferences.get(LOGIN_INFO_STORAGE_KEY, '') as string;
      if (loginInfoJson) {
        const loginInfoMap = SafeUtils.parseObj(loginInfoJson) as Record<string, string>;
        const keys = Object.keys(loginInfoMap);
        for (let i = 0; i < keys.length; i++) {
          this.loginInfoStore.set(keys[i], loginInfoMap[keys[i]]);
        }
        logger.info(TAG, `加载了 ${keys.length} 个书源的登录信息`);
      }
      
      // 加载登录头信息
      const loginHeaderJson = await this.dataPreferences.get(LOGIN_HEADER_STORAGE_KEY, '') as string;
      if (loginHeaderJson) {
        const loginHeaderMap = SafeUtils.parseObj(loginHeaderJson) as Record<string, string>;
        const keys = Object.keys(loginHeaderMap);
        for (let i = 0; i < keys.length; i++) {
          this.loginHeaderStore.set(keys[i], loginHeaderMap[keys[i]]);
        }
        logger.info(TAG, `加载了 ${keys.length} 个书源的登录头信息`);
      }
      
      // 加载书源变量
      const sourceVariableJson = await this.dataPreferences.get(SOURCE_VARIABLE_STORAGE_KEY, '') as string;
      if (sourceVariableJson) {
        const sourceVariableMap = SafeUtils.parseObj(sourceVariableJson) as Record<string, string>;
        const keys = Object.keys(sourceVariableMap);
        for (let i = 0; i < keys.length; i++) {
          this.sourceVariableStore.set(keys[i], sourceVariableMap[keys[i]]);
        }
        logger.info(TAG, `加载了 ${keys.length} 个书源变量`);
      }
      
      // 加载书源数据
      const sourceDataJson = await this.dataPreferences.get(SOURCE_DATA_STORAGE_KEY, '') as string;
      if (sourceDataJson) {
        const sourceDataMap = SafeUtils.parseObj(sourceDataJson) as Record<string, string>;
        const keys = Object.keys(sourceDataMap);
        for (let i = 0; i < keys.length; i++) {
          this.sourceDataStore.set(keys[i], sourceDataMap[keys[i]]);
        }
        logger.info(TAG, `加载了 ${keys.length} 个书源数据项`);
      }
      
      // 加载登录表单数据
      const loginFormDataJson = await this.dataPreferences.get(LOGIN_FORM_DATA_STORAGE_KEY, '') as string;
      if (loginFormDataJson) {
        const loginFormDataMap = SafeUtils.parseObj(loginFormDataJson) as Record<string, Record<string, string>>;
        const keys = Object.keys(loginFormDataMap);
        for (let i = 0; i < keys.length; i++) {
          this.loginFormDataStore.set(keys[i], loginFormDataMap[keys[i]]);
        }
        logger.info(TAG, `加载了 ${keys.length} 个书源的登录表单数据`);
      }
    } catch (error) {
      logger.error(TAG, `加载持久化数据失败: ${String(error)}`);
    }
  }

  /**
   * 保存持久化数据
   */
  async savePersistedData(): Promise<void> {
    if (!this.dataPreferences) {
      logger.warn(TAG, 'dataPreferences 未初始化，无法保存数据');
      return;
    }

    try {
      // 保存登录状态和Cookie
      const statusArray: SourceLoginStatus[] = [];
      this.loginStatus.forEach((status, sourceId) => {
        const cookies = this.cookies.get(sourceId);
        const statusWithCookies: SourceLoginStatus = {
          sourceId: status.sourceId,
          isLoggedIn: status.isLoggedIn,
          lastLoginTime: status.lastLoginTime,
          cookies: cookies
        };
        statusArray.push(statusWithCookies);
      });
      await this.dataPreferences.put(LOGIN_STATUS_STORAGE_KEY, JSON.stringify(statusArray));
      
      // 保存登录信息
      const loginInfoMap: Record<string, string> = {};
      this.loginInfoStore.forEach((value, key) => {
        loginInfoMap[key] = value;
      });
      await this.dataPreferences.put(LOGIN_INFO_STORAGE_KEY, JSON.stringify(loginInfoMap));
      
      // 保存登录头信息
      const loginHeaderMap: Record<string, string> = {};
      this.loginHeaderStore.forEach((value, key) => {
        loginHeaderMap[key] = value;
      });
      await this.dataPreferences.put(LOGIN_HEADER_STORAGE_KEY, JSON.stringify(loginHeaderMap));
      
      // 保存书源变量
      const sourceVariableMap: Record<string, string> = {};
      this.sourceVariableStore.forEach((value, key) => {
        sourceVariableMap[key] = value;
      });
      await this.dataPreferences.put(SOURCE_VARIABLE_STORAGE_KEY, JSON.stringify(sourceVariableMap));
      
      // 保存书源数据
      const sourceDataMap: Record<string, string> = {};
      this.sourceDataStore.forEach((value, key) => {
        sourceDataMap[key] = value;
      });
      await this.dataPreferences.put(SOURCE_DATA_STORAGE_KEY, JSON.stringify(sourceDataMap));
      
      // 保存登录表单数据
      const loginFormDataMap: Record<string, Record<string, string>> = {};
      this.loginFormDataStore.forEach((value, key) => {
        loginFormDataMap[key] = value;
      });
      await this.dataPreferences.put(LOGIN_FORM_DATA_STORAGE_KEY, JSON.stringify(loginFormDataMap));
      
      await this.dataPreferences.flush();
      logger.debug(TAG, `保存了 ${statusArray.length} 个书源的登录状态`);
    } catch (error) {
      logger.error(TAG, `保存持久化数据失败: ${String(error)}`);
    }
  }

  /**
   * 检查书源是否需要登录
   */
  needsLogin(source: LegadoBookSource): boolean {
    return !!source.loginUrl;
  }

  /**
   * 检查书源是否已登录
   */
  isLoggedIn(sourceId: string): boolean {
    const status = this.loginStatus.get(sourceId);
    return status?.isLoggedIn ?? false;
  }

  /**
   * 获取登录UI配置
   */
  getLoginUi(source: LegadoBookSource): LoginUiItem[] {
    if (!source.loginUi) {
      // 默认登录UI
      return [
        { type: 'text', name: 'username', hint: '用户名' },
        { type: 'password', name: 'password', hint: '密码' },
        { type: 'button', name: 'login', hint: '登录', action: 'login(true)' }
      ];
    }

    try {
      // 预处理：将单引号转换为双引号（某些书源的loginUi使用非标准JSON格式）
      let jsonStr = this.normalizeJsonString(source.loginUi);
      
      logger.debug(TAG, `预处理后的loginUi: ${jsonStr.substring(0, 200)}...`);
      
      const parsed = SafeUtils.parseArr(jsonStr) as LegadoLoginUiItem[];
      return parsed.map((item): LoginUiItem => {
        const uiItem: LoginUiItem = {
          type: item.type as 'text' | 'password' | 'button' | 'checkbox' | 'spinner',
          name: item.name,
          hint: item.hint,
          value: item.value,
          action: item.action
        };
        
        // 转换样式
        if (item.style) {
          uiItem.style = {
            flexGrow: item.style.layout_flexGrow,
            flexBasisPercent: item.style.layout_flexBasisPercent
          };
        }
        
        return uiItem;
      });
    } catch (e) {
      logger.warn(TAG, `解析loginUi失败: ${String(e)}`);
      return [];
    }
  }

  /**
   * 规范化JSON字符串（将非标准JSON转换为标准JSON）
   * 主要处理单引号替换为双引号的问题
   */
  private normalizeJsonString(jsonStr: string): string {
    // 方法：逐字符扫描，智能替换单引号
    let result = '';
    let inDoubleQuote = false;
    let inSingleQuote = false;
    let escapeNext = false;
    
    for (let i = 0; i < jsonStr.length; i++) {
      const char = jsonStr[i];
      
      if (escapeNext) {
        result += char;
        escapeNext = false;
        continue;
      }
      
      if (char === '\\') {
        result += char;
        escapeNext = true;
        continue;
      }
      
      if (char === '"' && !inSingleQuote) {
        inDoubleQuote = !inDoubleQuote;
        result += char;
        continue;
      }
      
      if (char === "'" && !inDoubleQuote) {
        // 单引号：判断是属性名/值的引号还是字符串内容中的撇号
        // 如果前一个非空白字符是 : , [ { 或者后一个非空白字符是 : , ] }
        // 则认为是JSON的引号，需要替换为双引号
        const beforeTrimmed = jsonStr.substring(0, i).replace(/\s+$/, '');
        const lastNonSpace = beforeTrimmed.length > 0 ? beforeTrimmed[beforeTrimmed.length - 1] : '';
        
        if (!inSingleQuote) {
          // 开始单引号字符串
          if (lastNonSpace === ':' || lastNonSpace === ',' || lastNonSpace === '[' || lastNonSpace === '{') {
            inSingleQuote = true;
            result += '"';
            continue;
          }
        } else {
          // 结束单引号字符串
          // 查看后面的非空白字符
          let afterTrimmed = jsonStr.substring(i + 1).replace(/^\s+/, '');
          const nextNonSpace = afterTrimmed.length > 0 ? afterTrimmed[0] : '';
          
          if (nextNonSpace === ':' || nextNonSpace === ',' || nextNonSpace === ']' || nextNonSpace === '}') {
            inSingleQuote = false;
            result += '"';
            continue;
          }
        }
        
        // 其他情况保持单引号（可能是字符串内容中的撇号）
        result += char;
        continue;
      }
      
      result += char;
    }
    
    return result;
  }

  /**
   * 获取保存的登录表单数据
   * @param sourceId 书源ID
   * @returns 保存的表单数据，如果没有则返回空对象
   */
  getLoginFormData(sourceId: string): Record<string, string> {
    return this.loginFormDataStore.get(sourceId) || {};
  }

  /**
   * 保存登录表单数据
   * @param sourceId 书源ID
   * @param formData 表单数据
   */
  async saveLoginFormData(sourceId: string, formData: Record<string, string>): Promise<void> {
    this.loginFormDataStore.set(sourceId, formData);
    await this.savePersistedData();
    logger.debug(TAG, `保存了书源 ${sourceId} 的登录表单数据`);
  }

  /**
   * 执行登录
   */
  async login(source: LegadoBookSource, formData: Record<string, string>): Promise<LoginResult> {
    if (!source.loginUrl) {
      return { success: false, message: '书源未配置登录URL' };
    }

    try {
      logger.info(TAG, `开始登录书源: ${source.bookSourceName}`);

      // 检查loginUrl是否是JS代码
      if (source.loginUrl.startsWith('@js:') || source.loginUrl.startsWith('<js>')) {
        return await this.executeJsLogin(source, formData);
      }

      // 普通URL登录
      return await this.executeUrlLogin(source, formData);
    } catch (error) {
      logger.error(TAG, `登录失败: ${String(error)}`);
      return { success: false, message: String(error) };
    }
  }

  /**
   * 执行JS登录
   */
  private async executeJsLogin(source: LegadoBookSource, formData: Record<string, string>): Promise<LoginResult> {
    const jsEngine = getLegadoRhinoEngine();
    
    // 提取JS代码
    let jsCode = source.loginUrl!;
    if (jsCode.startsWith('@js:')) {
      jsCode = jsCode.substring(4);
    } else if (jsCode.startsWith('<js>')) {
      const endIndex = jsCode.lastIndexOf('</js>');
      jsCode = jsCode.substring(4, endIndex > 0 ? endIndex : undefined);
    }

    // 执行JS
    const jsContext: JsContext = {
      variables: formData,
      jsLib: source.jsLib || ''
    };
    const result = await jsEngine.execute(jsCode, jsContext);

    if (result.success) {
      // 解析结果
      try {
        const loginResult = SafeUtils.parseObj(result.result) as Record<string, ESObject>;
        if (loginResult['success']) {
          this.setLoggedIn(source.bookSourceUrl, true, loginResult['cookies'] as Record<string, string>);
          return { 
            success: true, 
            message: '登录成功',
            cookies: loginResult['cookies'] as Record<string, string>
          };
        } else {
          return { 
            success: false, 
            message: loginResult['message'] as string || '登录失败' 
          };
        }
      } catch (e) {
        // 如果结果不是JSON，检查是否为空（表示成功）
        if (!result.result || result.result === 'true') {
          this.setLoggedIn(source.bookSourceUrl, true);
          return { success: true, message: '登录成功' };
        }
        return { success: false, message: result.result || '登录失败' };
      }
    } else {
      return { success: false, message: result.error || '登录失败' };
    }
  }

  /**
   * 执行URL登录
   */
  private async executeUrlLogin(source: LegadoBookSource, formData: Record<string, string>): Promise<LoginResult> {
    const inputKeys = Object.keys(formData);
    logger.warn(
      TAG,
      `URL登录需要页面级WebView表单提交链路，当前NovelLoginManager无可绑定WebView: source=${source.bookSourceName}, fields=${inputKeys.join(',')}`
    );
    return {
      success: false,
      message: 'URL登录需要图源配置提供 WebView 登录 workflow 或页面级 WebView 表单链路，当前仅支持 JS 登录。'
    };
  }

  /**
   * 执行按钮action（JS函数调用）
   * @param source 书源
   * @param action 要执行的JS函数名，如 "login(true)" 或 "register()"
   * @param formData 表单数据，会作为result变量传入JS环境
   */
  async executeButtonAction(source: LegadoBookSource, action: string, formData: Record<string, string>): Promise<LoginResult> {
    if (!action) {
      return { success: false, message: '未指定操作' };
    }

    try {
      logger.info(TAG, `执行按钮操作: ${action}, 书源: ${source.bookSourceName}`);
      
      const jsEngine = getLegadoRhinoEngine();
      const sourceId = source.bookSourceUrl;
      
      // 先保存登录信息（用户输入的表单数据）
      // 这样JS代码中的source.getLoginInfo()可以获取到
      this.putLoginInfo(sourceId, JSON.stringify(formData));
      
      // 构建完整的JS代码
      // loginUrl中包含了所有登录相关的函数定义
      // 我们需要先加载这些函数，然后调用action指定的函数
      let jsCode = '';
      
      // 如果有loginUrl，先加载它（包含函数定义）
      if (source.loginUrl) {
        let loginUrlCode = source.loginUrl;
        if (loginUrlCode.startsWith('@js:')) {
          loginUrlCode = loginUrlCode.substring(4);
        } else if (loginUrlCode.startsWith('<js>')) {
          const endIndex = loginUrlCode.lastIndexOf('</js>');
          loginUrlCode = loginUrlCode.substring(4, endIndex > 0 ? endIndex : undefined);
        }
        jsCode = loginUrlCode + '\n';
      }
      
      // 添加action调用
      jsCode += action;
      
      // 构建变量对象，包含登录信息
      const variables: Record<string, string> = {};
      const keys = Object.keys(formData);
      for (let i = 0; i < keys.length; i++) {
        variables[keys[i]] = formData[keys[i]];
      }
      variables['sourceUrl'] = sourceId;
      
      // 注入已保存的登录信息和书源变量
      variables['__loginInfo'] = this.getLoginInfo(sourceId);
      variables['__loginHeader'] = this.getLoginHeader(sourceId);
      variables['__sourceVariable'] = this.getSourceVariable(sourceId);
      
      // 执行JS，将formData作为result变量传入
      const jsContext: JsContext = {
        baseUrl: sourceId,
        result: JSON.stringify(formData),
        variables: variables,
        jsLib: source.jsLib || ''
      };
      const result = await jsEngine.execute(jsCode, jsContext);

      logger.info(TAG, `按钮操作执行结果: success=${result.success}, result=${result.result?.substring(0, 200)}`);

      // 显示Toast消息（如果有）
      if (result.toasts && result.toasts.length > 0) {
        this.showToasts(result.toasts);
      }
      
      // 同步Cookie变化到持久化存储
      if (result.cookieChanges && result.cookieChanges.length > 0) {
        await this.syncCookieChanges(result.cookieChanges);
      }

      if (result.success) {
        // 检查结果是否包含需要保存的数据
        this.processJsResult(sourceId, result.result);
        
        // 操作成功
        return { 
          success: true, 
          message: result.result || '操作成功'
        };
      } else {
        return { 
          success: false, 
          message: result.error || '操作失败' 
        };
      }
    } catch (error) {
      logger.error(TAG, `执行按钮操作失败: ${String(error)}`);
      return { success: false, message: String(error) };
    }
  }

  /**
   * 处理JS执行结果，提取需要保存的数据
   */
  private processJsResult(sourceId: string, resultStr: string | undefined): void {
    if (!resultStr) return;
    
    try {
      // 尝试解析为JSON
      const result = SafeUtils.parseObj(resultStr) as Record<string, ESObject>;
      
      // 检查是否有loginHeader需要保存
      if (result['loginHeader']) {
        const header = typeof result['loginHeader'] === 'string' 
          ? result['loginHeader'] 
          : JSON.stringify(result['loginHeader']);
        this.putLoginHeader(sourceId, header);
        logger.info(TAG, `保存登录头信息: ${sourceId}`);
      }
      
      // 检查是否有cookie需要保存
      if (result['cookie'] || result['Cookie']) {
        const cookieStr = (result['cookie'] || result['Cookie']) as string;
        this.parseCookieString(sourceId, cookieStr);
        logger.info(TAG, `保存Cookie: ${sourceId}`);
      }
      
      // 检查是否有variable需要保存
      if (result['variable'] !== undefined) {
        const variable = typeof result['variable'] === 'string'
          ? result['variable']
          : JSON.stringify(result['variable']);
        this.setSourceVariable(sourceId, variable);
        logger.info(TAG, `保存书源变量: ${sourceId}`);
      }
    } catch (e) {
      // 不是JSON格式，忽略
    }
  }

  /**
   * 显示Toast消息
   * @param toasts Toast消息列表
   */
  private showToasts(toasts: ToastMessage[]): void {
    for (const toast of toasts) {
      try {
        const duration = toast.type === 'long' ? 3500 : 2000;
        AppStorage.get<UIContext>('GlobalUIContext')?.getPromptAction()?.showToast({
          message: toast.msg,
          duration: duration
        });
        logger.debug(TAG, `显示Toast: ${toast.msg} (${toast.type})`);
      } catch (e) {
        logger.warn(TAG, `显示Toast失败: ${String(e)}`);
      }
    }
  }
  
  /**
   * 同步Cookie变化到持久化存储
   * @param changes Cookie变化列表
   */
  private async syncCookieChanges(changes: CookieChange[]): Promise<void> {
    const cookieStore = getCookieStore();
    
    for (const change of changes) {
      try {
        if (change.action === 'set' && change.value) {
          await cookieStore.setCookie(change.url, change.value);
          logger.debug(TAG, `Cookie已保存: ${change.url}`);
        } else if (change.action === 'remove') {
          await cookieStore.removeCookie(change.url);
          logger.debug(TAG, `Cookie已删除: ${change.url}`);
        }
      } catch (e) {
        logger.warn(TAG, `同步Cookie失败: ${String(e)}`);
      }
    }
  }

  /**
   * 检查登录状态
   */
  async checkLoginStatus(source: LegadoBookSource): Promise<boolean> {
    if (!source.loginCheckJs) {
      return this.isLoggedIn(source.bookSourceUrl);
    }

    try {
      const jsEngine = getLegadoRhinoEngine();
      const jsContext: JsContext = {
        variables: this.getVariables(source.bookSourceUrl),
        jsLib: source.jsLib || ''
      };
      const result = await jsEngine.execute(source.loginCheckJs, jsContext);

      const isLoggedIn = result.success && (result.result === 'true' || result.result === '1');
      this.setLoggedIn(source.bookSourceUrl, isLoggedIn);
      return isLoggedIn;
    } catch (error) {
      logger.warn(TAG, `检查登录状态失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 设置登录状态
   */
  setLoggedIn(sourceId: string, isLoggedIn: boolean, cookies?: Record<string, string>): void {
    this.loginStatus.set(sourceId, {
      sourceId,
      isLoggedIn,
      lastLoginTime: isLoggedIn ? Date.now() : undefined,
      cookies
    });

    if (cookies) {
      this.cookies.set(sourceId, cookies);
    }

    logger.info(TAG, `书源 ${sourceId} 登录状态: ${isLoggedIn}`);
    
    // 持久化保存
    this.savePersistedData();
  }

  /**
   * 获取书源的Cookie
   */
  getCookies(sourceId: string): Record<string, string> {
    return this.cookies.get(sourceId) || {};
  }

  /**
   * 设置Cookie
   */
  setCookies(sourceId: string, cookies: Record<string, string>): void {
    logger.info(TAG, `setCookies: sourceId=${sourceId}, cookieKeys=${Object.keys(cookies).join(',')}`);
    const existing = this.cookies.get(sourceId) || {};
    const merged: Record<string, string> = {};
    // 复制现有的cookies
    const existingKeys = Object.keys(existing);
    for (let i = 0; i < existingKeys.length; i++) {
      merged[existingKeys[i]] = existing[existingKeys[i]];
    }
    // 复制新的cookies
    const newKeys = Object.keys(cookies);
    for (let i = 0; i < newKeys.length; i++) {
      merged[newKeys[i]] = cookies[newKeys[i]];
    }
    this.cookies.set(sourceId, merged);
    logger.info(TAG, `Cookie已保存: sourceId=${sourceId}, 总共${Object.keys(merged).length}个cookie`);
    
    // 持久化保存
    this.savePersistedData();
  }

  /**
   * 获取Cookie字符串
   */
  getCookieString(sourceId: string): string {
    // 调试：输出所有已保存的Cookie keys
    const allKeys: string[] = [];
    this.cookies.forEach((_, key) => allKeys.push(key));
    logger.debug(TAG, `getCookieString: 查找=${sourceId}, 已保存的keys=[${allKeys.join(', ')}], initialized=${this.initialized}`);

    const candidateIds = this.buildCookieLookupCandidates(sourceId);
    for (let i = 0; i < candidateIds.length; i++) {
      const candidateId = candidateIds[i];
      const cookies = this.getCookies(candidateId);
      const keys = Object.keys(cookies);
      if (keys.length === 0) {
        continue;
      }

      const parts: string[] = [];
      for (let j = 0; j < keys.length; j++) {
        parts.push(`${keys[j]}=${cookies[keys[j]]}`);
      }
      if (candidateId !== sourceId) {
        logger.debug(TAG, `getCookieString: 命中候选ID=${candidateId}`);
      }
      return parts.join('; ');
    }

    return '';
  }

  /**
   * 构建Cookie查找候选ID（兼容带附加标识的书源ID）
   */
  private buildCookieLookupCandidates(sourceId: string): string[] {
    const candidates: string[] = [];
    this.pushUniqueCandidate(candidates, sourceId.trim());

    const normalizedSourceId = this.normalizeSourceId(sourceId);
    this.pushUniqueCandidate(candidates, normalizedSourceId);

    const domainOnlyId = this.extractDomainId(normalizedSourceId);
    this.pushUniqueCandidate(candidates, domainOnlyId);

    return candidates;
  }

  /**
   * 归一化书源ID（移除 ## 扩展段、片段标记）
   */
  private normalizeSourceId(sourceId: string): string {
    let normalized = sourceId.trim();
    const extensionSeparator = normalized.indexOf('##');
    if (extensionSeparator >= 0) {
      normalized = normalized.substring(0, extensionSeparator).trim();
    }

    const fragmentIndex = normalized.indexOf('#');
    if (fragmentIndex >= 0) {
      normalized = normalized.substring(0, fragmentIndex).trim();
    }

    return normalized;
  }

  /**
   * 提取域名级ID，兼容带路径和尾部斜杠的情况
   */
  private extractDomainId(sourceId: string): string {
    const match = sourceId.match(/^(https?:\/\/[^\/]+)/i);
    if (match) {
      return match[1];
    }
    return sourceId;
  }

  /**
   * 添加唯一候选ID
   */
  private pushUniqueCandidate(candidates: string[], candidate: string): void {
    if (candidate.length === 0) {
      return;
    }
    if (!candidates.includes(candidate)) {
      candidates.push(candidate);
    }
  }

  /**
   * 获取变量（用于JS执行）
   */
  private getVariables(sourceId: string): Record<string, string> {
    const cookies = this.getCookies(sourceId);
    const result: Record<string, string> = {};
    result['cookie'] = this.getCookieString(sourceId);
    // 复制cookies到result
    const keys = Object.keys(cookies);
    for (let i = 0; i < keys.length; i++) {
      result[keys[i]] = cookies[keys[i]];
    }
    return result;
  }

  // ========== 登录信息存储方法（兼容Legado原版） ==========

  /**
   * 保存登录信息（对应Legado的putLoginInfo）
   * @param sourceId 书源ID
   * @param info 登录信息JSON字符串
   */
  putLoginInfo(sourceId: string, info: string): boolean {
    try {
      this.loginInfoStore.set(sourceId, info);
      logger.info(TAG, `保存登录信息: sourceId=${sourceId}`);
      this.savePersistedData();
      return true;
    } catch (error) {
      logger.error(TAG, `保存登录信息失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 获取登录信息（对应Legado的getLoginInfo）
   */
  getLoginInfo(sourceId: string): string {
    return this.loginInfoStore.get(sourceId) || '';
  }

  /**
   * 获取登录信息Map（对应Legado的getLoginInfoMap）
   */
  getLoginInfoMap(sourceId: string): Record<string, string> {
    const info = this.getLoginInfo(sourceId);
    if (!info) return {};
    try {
      return SafeUtils.parseObj(info) as Record<string, string>;
    } catch (e) {
      return {};
    }
  }

  /**
   * 删除登录信息
   */
  removeLoginInfo(sourceId: string): void {
    this.loginInfoStore.delete(sourceId);
    this.savePersistedData();
  }

  /**
   * 保存登录头信息（对应Legado的putLoginHeader）
   */
  putLoginHeader(sourceId: string, header: string): void {
    this.loginHeaderStore.set(sourceId, header);
    // 如果header中包含Cookie，也保存到cookies中
    try {
      const headerMap = SafeUtils.parseObj(header) as Record<string, string>;
      const cookie = headerMap['Cookie'] || headerMap['cookie'];
      if (cookie) {
        this.parseCookieString(sourceId, cookie);
      }
    } catch (e) {
      // ignore
    }
    this.savePersistedData();
  }

  /**
   * 获取登录头信息（对应Legado的getLoginHeader）
   */
  getLoginHeader(sourceId: string): string {
    return this.loginHeaderStore.get(sourceId) || '';
  }

  /**
   * 获取登录头信息Map
   */
  getLoginHeaderMap(sourceId: string): Record<string, string> {
    const header = this.getLoginHeader(sourceId);
    if (!header) return {};
    try {
      return SafeUtils.parseObj(header) as Record<string, string>;
    } catch (e) {
      return {};
    }
  }

  /**
   * 删除登录头信息
   */
  removeLoginHeader(sourceId: string): void {
    this.loginHeaderStore.delete(sourceId);
    this.cookies.delete(sourceId);
    this.savePersistedData();
  }

  /**
   * 设置书源变量（对应Legado的source.setVariable）
   */
  setSourceVariable(sourceId: string, variable: string | null): void {
    if (variable !== null) {
      this.sourceVariableStore.set(sourceId, variable);
    } else {
      this.sourceVariableStore.delete(sourceId);
    }
    this.savePersistedData();
  }

  /**
   * 获取书源变量（对应Legado的source.getVariable）
   */
  getSourceVariable(sourceId: string): string {
    return this.sourceVariableStore.get(sourceId) || '';
  }

  /**
   * 保存数据（对应Legado的source.put）
   */
  putSourceData(sourceId: string, key: string, value: string): string {
    this.sourceDataStore.set(`${sourceId}_${key}`, value);
    this.savePersistedData();
    return value;
  }

  /**
   * 获取数据（对应Legado的source.get）
   */
  getSourceData(sourceId: string, key: string): string {
    return this.sourceDataStore.get(`${sourceId}_${key}`) || '';
  }

  /**
   * 获取书源持久化数据快照（对应Legado的source.get）
   */
  getSourceDataSnapshot(sourceId: string): Record<string, string> {
    const result: Record<string, string> = {};
    const prefix = `${sourceId}_`;
    this.sourceDataStore.forEach((value: string, key: string): void => {
      if (key.startsWith(prefix)) {
        const dataKey = key.substring(prefix.length);
        if (dataKey.length > 0) {
          result[dataKey] = value;
        }
      }
    });
    return result;
  }

  /**
   * 解析Cookie字符串并保存
   */
  private parseCookieString(sourceId: string, cookieStr: string): void {
    const cookies: Record<string, string> = {};
    const parts = cookieStr.split(';');
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i].trim();
      const eqIndex = part.indexOf('=');
      if (eqIndex > 0) {
        const key = part.substring(0, eqIndex).trim();
        const value = part.substring(eqIndex + 1).trim();
        cookies[key] = value;
      }
    }
    this.setCookies(sourceId, cookies);
  }

  /**
   * 登出
   */
  logout(sourceId: string): void {
    this.loginStatus.delete(sourceId);
    this.cookies.delete(sourceId);
    this.loginInfoStore.delete(sourceId);
    this.loginHeaderStore.delete(sourceId);
    logger.info(TAG, `书源 ${sourceId} 已登出`);
    this.savePersistedData();
  }

  /**
   * 清除所有登录状态
   */
  clearAll(): void {
    this.loginStatus.clear();
    this.cookies.clear();
    logger.info(TAG, '已清除所有登录状态');
  }
}

/**
 * 获取登录管理器实例
 */
export function getNovelLoginManager(): NovelLoginManager {
  return NovelLoginManager.getInstance();
}
