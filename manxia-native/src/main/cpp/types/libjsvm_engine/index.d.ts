/**
 * JSVM Engine - TypeScript 接口定义
 * 
 * 提供JavaScript代码执行能力的Native模块
 */

/**
 * JS执行结果
 */
export interface JsExecuteResult {
  /** 是否执行成功 */
  success: boolean;
  /** 执行结果或错误信息 */
  result: string;
}

/**
 * 创建一个新的虚拟机实例
 * @returns 虚拟机实例ID，失败返回-1
 */
export function createVm(): number;

/**
 * 销毁虚拟机实例
 * @param vmId 虚拟机实例ID
 */
export function destroyVm(vmId: number): void;

/**
 * 执行JavaScript代码
 * @param vmId 虚拟机实例ID
 * @param jsCode JavaScript代码字符串
 * @returns 执行结果
 */
export function executeJs(vmId: number, jsCode: string): JsExecuteResult;

/**
 * 设置全局字符串变量
 * @param vmId 虚拟机实例ID
 * @param name 变量名
 * @param value 字符串值
 * @returns 是否设置成功
 */
export function setGlobalString(vmId: number, name: string, value: string): boolean;

/**
 * 设置全局数字变量
 * @param vmId 虚拟机实例ID
 * @param name 变量名
 * @param value 数字值
 * @returns 是否设置成功
 */
export function setGlobalNumber(vmId: number, name: string, value: number): boolean;

/**
 * 获取当前活跃的虚拟机数量
 * @returns 虚拟机数量
 */
export function getVmCount(): number;
