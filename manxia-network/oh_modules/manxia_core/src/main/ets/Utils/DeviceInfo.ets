// 文件路径：entry/src/main/ets/Utils/DeviceInfo.ets
/**
 * 设备信息工具类
 * 提供获取设备相关信息、判断设备类型的静态方法
 */

import { display } from "@kit.ArkUI";
import { logger } from "./Logger";

const TAG = "DeviceInfo";

// 系统相关信息接口
interface SystemInfo {
  width: number;
  height: number;
  id: number;
  name: string;
  alive: boolean;
  refreshRate: number;
  rotation: number;
  densityDPI: number;
  

  // 其他系统相关信息...
}

/**
 * 收集各种系统、设备相关信息
 */
 export function collectDeviceInfo(): SystemInfo {
   try {
     const displayInfo = display.getDefaultDisplaySync();
     const info: SystemInfo = {
    width: displayInfo.width,
    height: displayInfo.height,
    id: displayInfo.id,
    name: displayInfo.name,
    alive: displayInfo.alive,
    refreshRate: displayInfo.refreshRate,
    rotation: displayInfo.rotation,
    densityDPI: displayInfo.densityDPI,
     }
     return info;
   } catch (error) {
     console.error("未能获取设备信息:", error);
     logger.error(TAG, "未能获取设备信息:" + error);
     return {} as SystemInfo;
   }
  };

/**
 * 获取设备屏幕宽度（像素）
 */
export function getScreenWidth(): number {
  return collectDeviceInfo().width;
}

/**
 * 获取设备屏幕高度（像素）
 */
export function getScreenHeight(): number {
  return collectDeviceInfo().height;
}

/**
 * 获取设备屏幕刷新率（赫兹）
 */
export function getScreenRefreshRate(): number {
  return collectDeviceInfo().refreshRate;
}

/**
 * 获取设备屏幕密度（DPI）
 */
export function getScreenDensityDPI(): number {
  return collectDeviceInfo().densityDPI;
}

/**
 * 获取设备屏幕旋转角度
 */
export function getScreenRotation(): number {
  return collectDeviceInfo().rotation;
}

/**
 * 判断设备布局
 * 为真则为紧凑布局（手机竖屏），为假则为中等布局（手机横屏/小平板）
 */
export function isCompactLayout(): boolean {
  return getScreenWidth() < getScreenHeight();
}