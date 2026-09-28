/**
 * QuickJS Engine TypeScript类型定义
 * 
 * 提供ArkTS调用QuickJS引擎的类型声明
 */

/**
 * 执行结果
 */
export interface ExecuteResult {
  /** 是否成功 */
  success: boolean;
  /** 执行结果 */
  result: string;
  /** 错误信息（失败时） */
  error?: string;
}

/**
 * 初始化QuickJS引擎
 * @returns 是否成功
 */
export function init(): boolean;

/**
 * 销毁QuickJS引擎
 * @returns 是否成功
 */
export function destroy(): boolean;

/**
 * 设置书源信息
 * @param sourceUrl 书源URL
 * @param sourceName 书源名称
 * @param jsLib JS库代码
 * @returns 是否成功
 */
export function setSourceInfo(sourceUrl: string, sourceName: string, jsLib: string): boolean;

/**
 * 执行JavaScript代码
 * @param code JS代码
 * @param key 搜索关键字
 * @param page 页码
 * @param result 上一步结果
 * @param baseUrl 基础URL
 * @returns 执行结果
 */
export function execute(code: string, key?: string, page?: number, result?: string, baseUrl?: string): ExecuteResult;

/**
 * 获取书源变量
 * @param sourceUrl 书源URL（可选）
 * @returns 变量值
 */
export function getSourceVariable(sourceUrl?: string): string;

/**
 * 设置书源变量
 * @param sourceUrl 书源URL
 * @param value 变量值
 * @returns 是否成功
 */
export function setSourceVariable(sourceUrl: string, value: string): boolean;

/**
 * 获取Cookie
 * @param url URL
 * @returns Cookie值
 */
export function getCookie(url: string): string;

/**
 * 设置Cookie
 * @param url URL
 * @param cookie Cookie值
 * @returns 是否成功
 */
export function setCookie(url: string, cookie: string): boolean;

/**
 * Base64编码
 * @param input 输入字符串
 * @returns 编码结果
 */
export function base64Encode(input: string): string;

/**
 * Base64解码
 * @param input 输入字符串
 * @returns 解码结果
 */
export function base64Decode(input: string): string;

/**
 * 十六进制解码
 * @param input 输入字符串
 * @returns 解码结果
 */
export function hexDecode(input: string): string;

/**
 * 获取引擎版本信息
 * @returns 版本信息
 */
export function getVersion(): string;
