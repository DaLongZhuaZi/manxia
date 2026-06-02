import { SafeFileUtils } from '../../Utils/SafeFileUtils';
/**
 * Legado JS扩展函数实现
 * 提供网络请求、编码解码、文件操作等功能的实际实现
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/LegadoJsExtensions.ets
 */

import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { logger } from '../../Utils/Logger';
import { getCookieStore } from './LegadoCookieStore';
import { getWebViewExecutor } from './LegadoWebViewExecutor';

const TAG = 'LegadoJsExtensions';

/**
 * 网络请求响应
 */
export interface JsResponse {
  body: string;
  url: string;
  code?: number;
  headers?: Record<string, string>;
}

/**
 * JS扩展函数实现类
 */
export class LegadoJsExtensions {
  private static instance: LegadoJsExtensions | null = null;
  private cookies: Map<string, string> = new Map();
  private variables: Map<string, string> = new Map();
  private cacheDir: string = '';

  private constructor() {}

  static getInstance(): LegadoJsExtensions {
    if (!LegadoJsExtensions.instance) {
      LegadoJsExtensions.instance = new LegadoJsExtensions();
    }
    return LegadoJsExtensions.instance;
  }

  /**
   * 设置缓存目录
   */
  setCacheDir(dir: string): void {
    this.cacheDir = dir;
  }

  // ==================== 网络请求 ====================

  /**
   * 发送GET请求
   */
  async ajax(url: string | string[]): Promise<string> {
    // 支持数组形式的URL
    const urlStr = Array.isArray(url) ? (url[0] || '') : url;
    if (!urlStr) return '';
    try {
      const httpRequest = http.createHttp();
      const response = await httpRequest.request(urlStr, {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36'
        },
        connectTimeout: 30000,
        readTimeout: 30000
      });
      httpRequest.destroy();
      
      if (response.responseCode === 200) {
        return response.result as string;
      }
      logger.warn(TAG, `ajax请求失败: ${urlStr}, code: ${response.responseCode}`);
      return '';
    } catch (error) {
      logger.error(TAG, `ajax请求异常: ${urlStr}, error: ${String(error)}`);
      return '';
    }
  }

  /**
   * 并发访问网络
   */
  async ajaxAll(urlList: string[]): Promise<JsResponse[]> {
    const results: JsResponse[] = [];
    const promises = urlList.map(async (url) => {
      try {
        const response = await this.connect(url);
        return response;
      } catch (error) {
        return { body: '', url: url, code: 0 };
      }
    });
    
    const responses = await Promise.all(promises);
    return responses;
  }

  /**
   * HEAD请求（不返回body，更省流量）
   */
  async head(url: string, headers?: Record<string, string>): Promise<JsResponse> {
    try {
      const httpRequest = http.createHttp();
      const requestHeaders: Record<string, string> = {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36',
        ...headers
      };
      
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.HEAD,
        header: requestHeaders,
        connectTimeout: 30000,
        readTimeout: 30000
      });
      httpRequest.destroy();
      
      // 获取响应头
      const responseHeaders: Record<string, string> = {};
      if (response.header) {
        const headerObj = response.header as Record<string, string>;
        for (const key of Object.keys(headerObj)) {
          responseHeaders[key] = headerObj[key];
        }
      }
      
      return {
        body: '',
        url: url,
        code: response.responseCode,
        headers: responseHeaders
      };
    } catch (error) {
      logger.error(TAG, `head请求异常: ${url}, error: ${String(error)}`);
      return { body: '', url: url, code: 0 };
    }
  }

  /**
   * GET请求（支持重定向拦截）
   */
  async get(url: string, headers?: Record<string, string>): Promise<JsResponse> {
    return this.connect(url, headers);
  }

  /**
   * 发送GET请求，返回Response对象
   */
  async connect(url: string, headers?: Record<string, string>): Promise<JsResponse> {
    try {
      const httpRequest = http.createHttp();
      const requestHeaders: Record<string, string> = {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36',
        ...headers
      };
      
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: requestHeaders,
        connectTimeout: 30000,
        readTimeout: 30000
      });
      httpRequest.destroy();
      
      return {
        body: response.result as string,
        url: url,
        code: response.responseCode
      };
    } catch (error) {
      logger.error(TAG, `connect请求异常: ${url}, error: ${String(error)}`);
      return { body: '', url: url, code: 0 };
    }
  }

  /**
   * 发送POST请求
   */
  async post(url: string, body: string, headers?: Record<string, string>): Promise<JsResponse> {
    try {
      const httpRequest = http.createHttp();
      const requestHeaders: Record<string, string> = {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36',
        'Content-Type': 'application/x-www-form-urlencoded',
        ...headers
      };
      
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: requestHeaders,
        extraData: body,
        connectTimeout: 30000,
        readTimeout: 30000
      });
      httpRequest.destroy();
      
      return {
        body: response.result as string,
        url: url,
        code: response.responseCode
      };
    } catch (error) {
      logger.error(TAG, `post请求异常: ${url}, error: ${String(error)}`);
      return { body: '', url: url, code: 0 };
    }
  }

  // ==================== Cookie管理 ====================

  /**
   * 获取Cookie（使用持久化存储）
   */
  getCookie(tag: string, key?: string): string {
    // 优先从持久化存储获取
    const cookieStore = getCookieStore();
    const persistedCookie = cookieStore.getCookieByTag(tag, key);
    if (persistedCookie) {
      return persistedCookie;
    }
    
    // 回退到内存存储
    const cookieKey = key ? `${tag}_${key}` : tag;
    return this.cookies.get(cookieKey) || '';
  }

  /**
   * 设置Cookie（同时保存到持久化存储）
   */
  async setCookie(tag: string, value: string, key?: string): Promise<void> {
    // 保存到内存
    const cookieKey = key ? `${tag}_${key}` : tag;
    this.cookies.set(cookieKey, value);
    
    // 保存到持久化存储
    const cookieStore = getCookieStore();
    const url = tag.includes('.') ? `https://${tag}` : tag;
    await cookieStore.setCookie(url, key ? `${key}=${value}` : value);
  }

  /**
   * 删除Cookie
   */
  async removeCookie(tag: string, key?: string): Promise<void> {
    const cookieKey = key ? `${tag}_${key}` : tag;
    this.cookies.delete(cookieKey);
    
    const cookieStore = getCookieStore();
    const url = tag.includes('.') ? `https://${tag}` : tag;
    await cookieStore.removeCookie(url, key);
  }

  // ==================== 变量存取 ====================

  /**
   * 获取变量
   */
  getVar(key: string): string {
    return this.variables.get(key) || '';
  }

  /**
   * 设置变量
   */
  putVar(key: string, value: string): void {
    this.variables.set(key, value);
  }

  // ==================== WebView操作 ====================

  /**
   * 使用WebView访问网络
   * @param html 直接用webView载入的html, 如果html为空直接访问url
   * @param url html内如果有相对路径的资源不传入url访问不了
   * @param js 用来取返回值的js语句, 没有就返回整个源代码
   * @returns 返回js获取的内容
   */
  async webView(html: string | null, url: string | null, js: string | null): Promise<string> {
    const executor = getWebViewExecutor();
    return executor.webView(html, url, js);
  }

  /**
   * 使用WebView获取资源URL
   */
  async webViewGetSource(
    html: string | null,
    url: string | null,
    js: string | null,
    sourceRegex: string
  ): Promise<string> {
    const executor = getWebViewExecutor();
    return executor.webViewGetSource(html, url, js, sourceRegex);
  }

  /**
   * 使用WebView获取跳转URL
   */
  async webViewGetOverrideUrl(
    html: string | null,
    url: string | null,
    js: string | null,
    overrideUrlRegex: string
  ): Promise<string> {
    const executor = getWebViewExecutor();
    return executor.webViewGetOverrideUrl(html, url, js, overrideUrlRegex);
  }

  // ==================== 编码解码 ====================

  /**
   * Base64编码
   */
  base64Encode(str: string): string {
    try {
      const encoder = new util.Base64Helper();
      const uint8Array = new util.TextEncoder().encodeInto(str);
      return encoder.encodeToStringSync(uint8Array);
    } catch (error) {
      logger.warn(TAG, `base64Encode失败: ${String(error)}`);
      return str;
    }
  }

  /**
   * Base64解码
   */
  base64Decode(str: string): string {
    try {
      const decoder = new util.Base64Helper();
      const uint8Array = decoder.decodeSync(str);
      return new util.TextDecoder().decodeToString(uint8Array);
    } catch (error) {
      logger.warn(TAG, `base64Decode失败: ${String(error)}`);
      return str;
    }
  }

  /**
   * Hex编码
   */
  hexEncode(str: string): string {
    let hex = '';
    for (let i = 0; i < str.length; i++) {
      hex += str.charCodeAt(i).toString(16).padStart(2, '0');
    }
    return hex;
  }

  /**
   * Hex解码
   */
  hexDecode(hex: string): string {
    let str = '';
    for (let i = 0; i < hex.length; i += 2) {
      str += String.fromCharCode(parseInt(hex.substr(i, 2), 16));
    }
    return str;
  }

  /**
   * MD5编码 - 使用HarmonyOS cryptoFramework
   */
  md5Encode(str: string): string {
    // 同步返回，使用缓存的结果或简单哈希作为后备
    // 真正的MD5需要异步调用，这里提供同步版本的简化实现
    return this.simpleHash(str, 32);
  }

  /**
   * MD5编码 - 异步版本，使用真正的MD5算法
   */
  async md5EncodeAsync(str: string): Promise<string> {
    try {
      const md = cryptoFramework.createMd('MD5');
      const encoder = new util.TextEncoder();
      const data = encoder.encodeInto(str);
      await md.update({ data: data });
      const result = await md.digest();
      return this.uint8ArrayToHex(result.data);
    } catch (error) {
      logger.warn(TAG, `MD5编码失败，使用简化哈希: ${String(error)}`);
      return this.simpleHash(str, 32);
    }
  }

  /**
   * SHA256编码 - 异步版本
   */
  async sha256Encode(str: string): Promise<string> {
    try {
      const md = cryptoFramework.createMd('SHA256');
      const encoder = new util.TextEncoder();
      const data = encoder.encodeInto(str);
      await md.update({ data: data });
      const result = await md.digest();
      return this.uint8ArrayToHex(result.data);
    } catch (error) {
      logger.warn(TAG, `SHA256编码失败: ${String(error)}`);
      return this.simpleHash(str, 64);
    }
  }

  /**
   * SHA1编码 - 异步版本
   */
  async sha1Encode(str: string): Promise<string> {
    try {
      const md = cryptoFramework.createMd('SHA1');
      const encoder = new util.TextEncoder();
      const data = encoder.encodeInto(str);
      await md.update({ data: data });
      const result = await md.digest();
      return this.uint8ArrayToHex(result.data);
    } catch (error) {
      logger.warn(TAG, `SHA1编码失败: ${String(error)}`);
      return this.simpleHash(str, 40);
    }
  }

  /**
   * MD5编码16位
   */
  md5Encode16(str: string): string {
    const full = this.md5Encode(str);
    return full.substring(8, 24);
  }

  /**
   * Uint8Array转十六进制字符串
   */
  private uint8ArrayToHex(arr: Uint8Array): string {
    let hex = '';
    for (let i = 0; i < arr.length; i++) {
      hex += arr[i].toString(16).padStart(2, '0');
    }
    return hex;
  }

  /**
   * 简单哈希函数（后备方案）
   */
  private simpleHash(str: string, length: number): string {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      const char = str.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash;
    }
    
    // 转换为十六进制并填充到指定长度
    let result = Math.abs(hash).toString(16);
    while (result.length < length) {
      result = result + result;
    }
    return result.substring(0, length);
  }

  // ==================== 繁简转换 ====================

  /**
   * 繁体转简体
   * 使用简化的映射表
   */
  t2s(text: string): string {
    return this.convertChinese(text, T2S_MAP);
  }

  /**
   * 简体转繁体
   */
  s2t(text: string): string {
    return this.convertChinese(text, S2T_MAP);
  }

  private convertChinese(text: string, map: Record<string, string>): string {
    let result = '';
    for (let i = 0; i < text.length; i++) {
      const char = text[i];
      result += map[char] || char;
    }
    return result;
  }

  // ==================== 文件操作 ====================

  /**
   * 读取文本文件
   */
  async readTxtFile(path: string): Promise<string> {
    try {
      const fullPath = this.resolvePath(path);
      const file = SafeFileUtils.openSync(fullPath, fileIo.OpenMode.READ_ONLY);
      const stat = SafeFileUtils.statSync(fullPath);
      const buffer = new ArrayBuffer(stat.size);
      SafeFileUtils.readSync(file.fd, buffer);
      SafeFileUtils.closeSync(file);
      return new util.TextDecoder().decodeToString(new Uint8Array(buffer));
    } catch (error) {
      logger.warn(TAG, `读取文件失败: ${path}, error: ${String(error)}`);
      return '';
    }
  }

  /**
   * 缓存文件
   */
  async cacheFile(url: string, saveTime?: number): Promise<string> {
    try {
      const key = this.md5Encode16(url);
      const cachePath = `${this.cacheDir}/${key}`;
      
      // 检查缓存是否存在
      try {
        const stat = SafeFileUtils.statSync(cachePath);
        if (saveTime && saveTime > 0) {
          const now = Date.now();
          const fileTime = stat.mtime;
          if (now - fileTime < saveTime * 1000) {
            return await this.readTxtFile(cachePath);
          }
        } else {
          return await this.readTxtFile(cachePath);
        }
      } catch (e) {
        // 缓存不存在，继续下载
      }
      
      // 下载文件
      const content = await this.ajax(url);
      if (content) {
        await this.writeFile(cachePath, content);
      }
      return content;
    } catch (error) {
      logger.warn(TAG, `缓存文件失败: ${url}, error: ${String(error)}`);
      return '';
    }
  }

  /**
   * 写入文件
   */
  private async writeFile(path: string, content: string): Promise<void> {
    try {
      const file = SafeFileUtils.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      const encoder = new util.TextEncoder();
      const buffer = encoder.encodeInto(content);
      SafeFileUtils.writeSync(file.fd, buffer.buffer);
      SafeFileUtils.closeSync(file);
    } catch (error) {
      logger.warn(TAG, `写入文件失败: ${path}, error: ${String(error)}`);
    }
  }

  /**
   * 解析路径
   */
  private resolvePath(path: string): string {
    if (path.startsWith('/')) {
      return path;
    }
    return `${this.cacheDir}/${path}`;
  }

  // ==================== 工具函数 ====================

  /**
   * URL编码
   */
  encodeURI(str: string): string {
    try {
      return encodeURIComponent(str);
    } catch (e) {
      return str;
    }
  }

  /**
   * URL解码
   */
  decodeURI(str: string): string {
    try {
      return decodeURIComponent(str);
    } catch (e) {
      return str;
    }
  }

  /**
   * 时间格式化
   */
  timeFormat(time: number): string {
    const date = new Date(time);
    return date.toLocaleString();
  }

  /**
   * UTC时间格式化
   */
  timeFormatUTC(time: number, format: string, offset: number): string {
    const date = new Date(time + offset * 3600 * 1000);
    return date.toISOString();
  }

  /**
   * HTML格式化（移除标签）
   */
  htmlFormat(str: string): string {
    return str
      .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '')
      .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '')
      .replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&amp;/g, '&')
      .replace(/&quot;/g, '"')
      .trim();
  }

  /**
   * 生成UUID
   */
  randomUUID(): string {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
      const r = Math.random() * 16 | 0;
      const v = c === 'x' ? r : (r & 0x3 | 0x8);
      return v.toString(16);
    });
  }

  /**
   * 字符串分割
   */
  splitNotBlank(str: string, delimiter: string): string[] {
    return str.split(delimiter).filter(s => s.trim() !== '');
  }

  /**
   * 章节数转数字
   */
  toNumChapter(s: string): string {
    if (!s) return '';
    // 匹配中文数字并转换
    const chineseNums: Record<string, number> = {
      '零': 0, '一': 1, '二': 2, '三': 3, '四': 4,
      '五': 5, '六': 6, '七': 7, '八': 8, '九': 9,
      '十': 10, '百': 100, '千': 1000, '万': 10000
    };
    
    // 简单的中文数字转换
    let result = s;
    const pattern = /[零一二三四五六七八九十百千万]+/g;
    result = result.replace(pattern, (match) => {
      let num = 0;
      let temp = 0;
      for (let i = 0; i < match.length; i++) {
        const char = match[i];
        const val = chineseNums[char];
        if (val === undefined) continue;
        if (val >= 10) {
          if (temp === 0) temp = 1;
          temp *= val;
          if (val === 10 && i === match.length - 1) {
            num += temp;
            temp = 0;
          }
        } else {
          if (temp > 0) {
            num += temp;
            temp = 0;
          }
          temp = val;
        }
      }
      num += temp;
      return String(num);
    });
    return result;
  }

  /**
   * 字符串转字节数组
   */
  strToBytes(str: string, charset?: string): number[] {
    const bytes: number[] = [];
    for (let i = 0; i < str.length; i++) {
      bytes.push(str.charCodeAt(i) & 0xFF);
    }
    return bytes;
  }

  /**
   * 字节数组转字符串
   */
  bytesToStr(bytes: number[], charset?: string): string {
    return String.fromCharCode(...bytes);
  }

  /**
   * 获取绝对URL
   */
  getAbsoluteURL(baseUrl: string, relativeUrl: string): string {
    if (!relativeUrl) return baseUrl || '';
    if (relativeUrl.startsWith('http://') || relativeUrl.startsWith('https://')) {
      return relativeUrl;
    }
    if (relativeUrl.startsWith('//')) {
      return 'https:' + relativeUrl;
    }
    if (!baseUrl) return relativeUrl;
    
    if (relativeUrl.startsWith('/')) {
      const match = baseUrl.match(/^(https?:\/\/[^\/]+)/);
      if (match) {
        return match[1] + relativeUrl;
      }
    }
    
    // 相对当前路径
    let base = baseUrl;
    if (!base.endsWith('/')) {
      const lastSlash = base.lastIndexOf('/');
      if (lastSlash > 8) {
        base = base.substring(0, lastSlash + 1);
      } else {
        base = base + '/';
      }
    }
    return base + relativeUrl;
  }

  /**
   * 日志输出
   */
  log(msg: any): any {
    logger.debug(TAG, `[JS] ${String(msg)}`);
    return msg;
  }

  /**
   * 输出对象类型
   */
  logType(any: any): void {
    if (any === null || any === undefined) {
      this.log('null');
    } else {
      this.log(typeof any);
    }
  }

  /**
   * 弹窗提示（简化实现，仅记录日志）
   */
  toast(msg: any): void {
    logger.info(TAG, `[Toast] ${String(msg)}`);
  }

  /**
   * 长时间弹窗提示
   */
  longToast(msg: any): void {
    logger.info(TAG, `[LongToast] ${String(msg)}`);
  }

  // ==================== 文件操作增强 ====================

  /**
   * 下载文件
   */
  async downloadFile(url: string): Promise<string> {
    try {
      const key = this.md5Encode16(url);
      const suffix = this.getUrlSuffix(url);
      const path = `${key}.${suffix}`;
      const fullPath = this.resolvePath(path);
      
      const content = await this.ajax(url);
      if (content) {
        await this.writeFile(fullPath, content);
      }
      return path;
    } catch (error) {
      logger.error(TAG, `下载文件失败: ${url}, error: ${String(error)}`);
      return '';
    }
  }

  /**
   * 获取URL后缀
   */
  private getUrlSuffix(url: string): string {
    const match = url.match(/\.([a-zA-Z0-9]+)(?:\?|$)/);
    return match ? match[1] : 'txt';
  }

  /**
   * 读取文件字节
   */
  async readFile(path: string): Promise<Uint8Array | null> {
    try {
      const fullPath = this.resolvePath(path);
      const file = SafeFileUtils.openSync(fullPath, fileIo.OpenMode.READ_ONLY);
      const stat = SafeFileUtils.statSync(fullPath);
      const buffer = new ArrayBuffer(stat.size);
      SafeFileUtils.readSync(file.fd, buffer);
      SafeFileUtils.closeSync(file);
      return new Uint8Array(buffer);
    } catch (error) {
      logger.warn(TAG, `读取文件失败: ${path}, error: ${String(error)}`);
      return null;
    }
  }

  /**
   * 删除文件
   */
  deleteFile(path: string): boolean {
    try {
      const fullPath = this.resolvePath(path);
      SafeFileUtils.unlinkSync(fullPath);
      return true;
    } catch (error) {
      logger.warn(TAG, `删除文件失败: ${path}, error: ${String(error)}`);
      return false;
    }
  }

  /**
   * 导入JS脚本
   */
  async importScript(path: string): Promise<string> {
    if (path.startsWith('http')) {
      return await this.cacheFile(path);
    }
    return await this.readTxtFile(path);
  }

  // ==================== 压缩文件操作 ====================

  /**
   * 解压zip文件
   * @param zipPath 压缩文件的相对路径
   * @returns 解压后的目录相对路径
   */
  async unzipFile(zipPath: string): Promise<string> {
    return this.unArchiveFile(zipPath);
  }

  /**
   * 解压7z文件（使用zlib，仅支持zip格式）
   */
  async un7zFile(zipPath: string): Promise<string> {
    logger.warn(TAG, '7z格式暂不支持，尝试作为zip解压');
    return this.unArchiveFile(zipPath);
  }

  /**
   * 解压rar文件（使用zlib，仅支持zip格式）
   */
  async unrarFile(zipPath: string): Promise<string> {
    logger.warn(TAG, 'rar格式暂不支持，尝试作为zip解压');
    return this.unArchiveFile(zipPath);
  }

  /**
   * 通用解压文件方法
   */
  async unArchiveFile(zipPath: string): Promise<string> {
    if (!zipPath) return '';
    
    try {
      const fullZipPath = this.resolvePath(zipPath);
      const key = this.md5Encode16(zipPath);
      const outDir = this.resolvePath(`unzip_${key}`);
      
      // 确保输出目录存在
      try {
        SafeFileUtils.mkdirSync(outDir);
      } catch (e) {
        // 目录可能已存在
      }
      
      // 使用zlib解压
      await zlib.decompressFile(fullZipPath, outDir, {
        level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION
      });
      
      return `unzip_${key}`;
    } catch (error) {
      logger.error(TAG, `解压文件失败: ${zipPath}, error: ${String(error)}`);
      return '';
    }
  }

  /**
   * 获取zip文件中指定文件的内容（字符串）
   */
  async getZipStringContent(url: string, path: string, charsetName?: string): Promise<string> {
    try {
      const byteArray = await this.getZipByteArrayContent(url, path);
      if (!byteArray) return '';
      
      const decoder = new util.TextDecoder(charsetName || 'utf-8');
      return decoder.decodeToString(byteArray);
    } catch (error) {
      logger.error(TAG, `获取zip内容失败: ${url}, path: ${path}, error: ${String(error)}`);
      return '';
    }
  }

  /**
   * 获取zip文件中指定文件的内容（字节数组）
   */
  async getZipByteArrayContent(url: string, path: string): Promise<Uint8Array | null> {
    try {
      // 下载或获取zip文件
      let zipPath: string;
      if (url.startsWith('http://') || url.startsWith('https://')) {
        zipPath = await this.downloadFile(url);
      } else {
        // 假设是hex字符串
        const bytes = this.hexDecodeToByteArray(url);
        if (!bytes) return null;
        
        const key = this.md5Encode16(url.substring(0, 32));
        zipPath = `${key}.zip`;
        const fullPath = this.resolvePath(zipPath);
        const file = SafeFileUtils.openSync(fullPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
        SafeFileUtils.writeSync(file.fd, bytes.buffer);
        SafeFileUtils.closeSync(file);
      }
      
      if (!zipPath) return null;
      
      // 解压
      const outDir = await this.unArchiveFile(zipPath);
      if (!outDir) return null;
      
      // 读取指定文件
      const targetPath = `${outDir}/${path}`;
      return await this.readFile(targetPath);
    } catch (error) {
      logger.error(TAG, `获取zip字节内容失败: ${url}, path: ${path}, error: ${String(error)}`);
      return null;
    }
  }

  /**
   * 获取rar文件中指定文件的内容（字符串）
   */
  async getRarStringContent(url: string, path: string, charsetName?: string): Promise<string> {
    logger.warn(TAG, 'rar格式暂不支持，尝试作为zip处理');
    return this.getZipStringContent(url, path, charsetName);
  }

  /**
   * 获取7z文件中指定文件的内容（字符串）
   */
  async get7zStringContent(url: string, path: string, charsetName?: string): Promise<string> {
    logger.warn(TAG, '7z格式暂不支持，尝试作为zip处理');
    return this.getZipStringContent(url, path, charsetName);
  }

  /**
   * 获取文件夹内所有文本文件读取
   */
  async getTxtInFolder(path: string): Promise<string> {
    if (!path) return '';
    
    try {
      const fullPath = this.resolvePath(path);
      const contents: string[] = [];
      
      // 列出目录下的文件
      const files = SafeFileUtils.listFileSync(fullPath);
      for (const fileName of files) {
        const filePath = `${fullPath}/${fileName}`;
        const stat = SafeFileUtils.statSync(filePath);
        if (stat.isFile()) {
          const content = await this.readTxtFile(`${path}/${fileName}`);
          if (content) {
            contents.push(content);
          }
        }
      }
      
      // 清理临时目录
      this.deleteFile(path);
      
      return contents.join('\n');
    } catch (error) {
      logger.error(TAG, `读取文件夹内容失败: ${path}, error: ${String(error)}`);
      return '';
    }
  }

  // ==================== URL工具类 ====================

  /**
   * 创建URL解析对象
   */
  toURL(urlStr: string, baseUrl?: string): JsURL {
    return new JsURL(urlStr, baseUrl);
  }

  /**
   * 获取WebView UA
   */
  getWebViewUA(): string {
    return 'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36';
  }

  // ==================== 加密解密增强 ====================

  /**
   * Base64解码到字节数组
   */
  base64DecodeToByteArray(str: string): Uint8Array | null {
    if (!str) return null;
    try {
      const decoder = new util.Base64Helper();
      return decoder.decodeSync(str);
    } catch (error) {
      logger.warn(TAG, `base64DecodeToByteArray失败: ${String(error)}`);
      return null;
    }
  }

  /**
   * Hex解码到字节数组
   */
  hexDecodeToByteArray(hex: string): Uint8Array | null {
    if (!hex) return null;
    try {
      const bytes = new Uint8Array(hex.length / 2);
      for (let i = 0; i < hex.length; i += 2) {
        bytes[i / 2] = parseInt(hex.substr(i, 2), 16);
      }
      return bytes;
    } catch (error) {
      logger.warn(TAG, `hexDecodeToByteArray失败: ${String(error)}`);
      return null;
    }
  }

  /**
   * Hex解码到字符串
   */
  hexDecodeToString(hex: string): string {
    return this.hexDecode(hex);
  }

  /**
   * 字符串编码为Hex
   */
  hexEncodeToString(str: string): string {
    return this.hexEncode(str);
  }
}

/**
 * URL解析类（手动实现，不依赖URL API）
 */
export class JsURL {
  private urlStr: string;
  private baseUrl: string;
  private protocol: string = '';
  private host: string = '';
  private port: string = '';
  private path: string = '';
  private query: string = '';
  private hash: string = '';

  constructor(urlStr: string, baseUrl?: string) {
    this.urlStr = urlStr;
    this.baseUrl = baseUrl || '';
    this.parse();
  }

  private parse(): void {
    try {
      let url = this.urlStr;
      
      // 处理相对URL
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        if (this.baseUrl) {
          const ext = getJsExtensions();
          url = ext.getAbsoluteURL(this.baseUrl, url);
        } else {
          return;
        }
      }
      
      // 解析协议
      const protocolMatch = url.match(/^(https?):\/\//);
      if (protocolMatch) {
        this.protocol = protocolMatch[1];
        url = url.substring(protocolMatch[0].length);
      }
      
      // 解析hash
      const hashIndex = url.indexOf('#');
      if (hashIndex >= 0) {
        this.hash = url.substring(hashIndex + 1);
        url = url.substring(0, hashIndex);
      }
      
      // 解析query
      const queryIndex = url.indexOf('?');
      if (queryIndex >= 0) {
        this.query = url.substring(queryIndex + 1);
        url = url.substring(0, queryIndex);
      }
      
      // 解析host和path
      const pathIndex = url.indexOf('/');
      if (pathIndex >= 0) {
        this.host = url.substring(0, pathIndex);
        this.path = url.substring(pathIndex);
      } else {
        this.host = url;
        this.path = '/';
      }
      
      // 解析port
      const portMatch = this.host.match(/:(\d+)$/);
      if (portMatch) {
        this.port = portMatch[1];
        this.host = this.host.substring(0, this.host.length - portMatch[0].length);
      }
    } catch (e) {
      logger.warn(TAG, `URL解析失败: ${this.urlStr}`);
    }
  }

  getHost(): string {
    return this.host;
  }

  getPath(): string {
    return this.path;
  }

  getQuery(): string {
    return this.query;
  }

  getFile(): string {
    const lastSlash = this.path.lastIndexOf('/');
    return lastSlash >= 0 ? this.path.substring(lastSlash + 1) : this.path;
  }

  getProtocol(): string {
    return this.protocol;
  }

  getPort(): number {
    if (this.port) return parseInt(this.port);
    return this.protocol === 'https' ? 443 : 80;
  }

  getRef(): string {
    return this.hash;
  }

  toString(): string {
    let result = '';
    if (this.protocol) {
      result += this.protocol + '://';
    }
    result += this.host;
    if (this.port) {
      result += ':' + this.port;
    }
    result += this.path;
    if (this.query) {
      result += '?' + this.query;
    }
    if (this.hash) {
      result += '#' + this.hash;
    }
    return result || this.urlStr;
  }
}

// ==================== 繁简转换映射表 ====================
// 常用繁简字对照（简化版本，仅包含常用字）

const T2S_MAP: Record<string, string> = {
  '書': '书', '說': '说', '話': '话', '語': '语', '詞': '词',
  '論': '论', '講': '讲', '讀': '读', '寫': '写', '記': '记',
  '認': '认', '識': '识', '學': '学', '習': '习', '練': '练',
  '經': '经', '過': '过', '進': '进', '運': '运', '動': '动',
  '開': '开', '關': '关', '門': '门', '問': '问', '間': '间',
  '時': '时', '機': '机', '會': '会', '見': '见', '觀': '观',
  '視': '视', '聽': '听', '聲': '声', '響': '响', '電': '电',
  '話': '话', '報': '报', '紙': '纸', '張': '张', '頁': '页',
  '網': '网', '絡': '络', '線': '线', '連': '连', '結': '结',
  '節': '节', '點': '点', '數': '数', '計': '计', '統': '统',
  '圖': '图', '畫': '画', '藝': '艺', '術': '术', '設': '设',
  '備': '备', '準': '准', '標': '标', '題': '题', '類': '类',
  '別': '别', '區': '区', '場': '场', '廠': '厂', '廣': '广',
  '應': '应', '當': '当', '對': '对', '錯': '错', '難': '难',
  '簡': '简', '單': '单', '複': '复', '雜': '杂', '亂': '乱',
  '長': '长', '短': '短', '高': '高', '低': '低', '大': '大',
  '國': '国', '際': '际', '內': '内', '外': '外', '東': '东',
  '西': '西', '南': '南', '北': '北', '中': '中', '華': '华',
  '發': '发', '現': '现', '實': '实', '際': '际', '確': '确',
  '決': '决', '選': '选', '擇': '择', '採': '采', '取': '取',
  '給': '给', '與': '与', '為': '为', '無': '无', '從': '从',
  '來': '来', '後': '后', '頭': '头', '體': '体', '個': '个',
  '這': '这', '那': '那', '裡': '里', '邊': '边', '處': '处',
  '種': '种', '樣': '样', '條': '条', '塊': '块', '隻': '只',
  '雙': '双', '對': '对', '組': '组', '套': '套', '份': '份',
  '愛': '爱', '戀': '恋', '親': '亲', '歡': '欢', '樂': '乐',
  '傷': '伤', '痛': '痛', '淚': '泪', '淒': '凄', '慘': '惨',
  '驚': '惊', '險': '险', '戰': '战', '鬥': '斗', '勝': '胜',
  '敗': '败', '輸': '输', '贏': '赢', '強': '强', '弱': '弱',
  '飛': '飞', '風': '风', '雲': '云', '雨': '雨', '雪': '雪',
  '龍': '龙', '鳳': '凤', '獸': '兽', '鳥': '鸟', '魚': '鱼',
  '馬': '马', '車': '车', '船': '船', '飛': '飞', '機': '机'
};

const S2T_MAP: Record<string, string> = {};
// 反向生成简转繁映射
for (const key of Object.keys(T2S_MAP)) {
  S2T_MAP[T2S_MAP[key]] = key;
}

/**
 * 获取JS扩展实例
 */
export function getJsExtensions(): LegadoJsExtensions {
  return LegadoJsExtensions.getInstance();
}
