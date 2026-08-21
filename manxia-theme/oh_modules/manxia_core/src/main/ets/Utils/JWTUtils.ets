import { SafeUtils } from '../Utils/SafeUtils';
/**
 * JWT工具类
 * 提供JWT令牌的解析和验证功能
 */

import { base64UrlDecode } from './CryptoUtils';
import { logger } from './Logger';

const TAG = 'JWTUtils';

/**
 * JWT载荷接口
 */
export interface JWTPayload {
  exp?: number;  // 过期时间（秒级时间戳）
  iat?: number;  // 签发时间（秒级时间戳）
  [key: string]: ESObject;  // 其他自定义字段
}

/**
 * JWT令牌结构
 */
export interface JWTToken {
  header: ESObject;
  payload: JWTPayload;
  signature: string;
  raw: string;
}

/**
 * 解析JWT令牌
 * @param token JWT令牌字符串
 * @returns 解析后的JWT对象
 */
export function parseJWT(token: string): JWTToken {
  try {
    // JWT格式: header.payload.signature
    const parts = token.split('.');
    
    if (parts.length !== 3) {
      throw new Error(`Invalid JWT format: expected 3 parts, got ${parts.length}`);
    }
    
    const [headerStr, payloadStr, signature] = parts;
    
    // 解码header
    const headerJson = base64UrlDecode(headerStr);
    const header = SafeUtils.parseObj(headerJson) as ESObject;
    
    // 解码payload
    const payloadJson = base64UrlDecode(payloadStr);
    const payload = SafeUtils.parseObj(payloadJson) as JWTPayload;
    
    return {
      header,
      payload,
      signature,
      raw: token
    };
  } catch (error) {
    logger.error(TAG, `JWT解析失败: ${error}`);
    throw error;
  }
}

/**
 * 检查JWT令牌是否过期
 * @param token JWT令牌字符串或已解析的JWT对象
 * @param leeway 时间误差容忍度（秒），默认10秒
 * @returns true表示已过期，false表示未过期
 */
export function isJWTExpired(token: string | JWTToken, leeway: number = 10): boolean {
  try {
    const jwt = typeof token === 'string' ? parseJWT(token) : token;
    const payload = jwt.payload;
    
    // 获取当前时间（秒级时间戳）
    const nowSeconds = Math.floor(Date.now() / 1000);
    const futureNow = nowSeconds + leeway;
    const pastNow = nowSeconds - leeway;
    
    // 检查过期时间
    const expValid = payload.exp === undefined || payload.exp > pastNow;
    
    // 检查签发时间（不能是未来时间）
    const iatValid = payload.iat === undefined || payload.iat < futureNow;
    
    // 如果exp或iat无效，则认为令牌已过期
    const isExpired = !expValid || !iatValid;
    
    if (isExpired) {
      logger.debug(TAG, `JWT已过期: exp=${payload.exp}, iat=${payload.iat}, now=${nowSeconds}`);
    }
    
    return isExpired;
  } catch (error) {
    logger.error(TAG, `JWT过期检查失败: ${error}`);
    // 如果解析失败，认为令牌无效（已过期）
    return true;
  }
}

/**
 * 获取JWT令牌的剩余有效时间（秒）
 * @param token JWT令牌字符串或已解析的JWT对象
 * @returns 剩余有效时间（秒），如果已过期返回0
 */
export function getJWTRemainingTime(token: string | JWTToken): number {
  try {
    const jwt = typeof token === 'string' ? parseJWT(token) : token;
    const payload = jwt.payload;
    
    if (!payload.exp) {
      // 没有过期时间，认为永久有效
      return Number.MAX_SAFE_INTEGER;
    }
    
    const nowSeconds = Math.floor(Date.now() / 1000);
    const remaining = payload.exp - nowSeconds;
    
    return Math.max(0, remaining);
  } catch (error) {
    logger.error(TAG, `获取JWT剩余时间失败: ${error}`);
    return 0;
  }
}

/**
 * 验证JWT令牌的基本有效性（不验证签名）
 * @param token JWT令牌字符串
 * @param leeway 时间误差容忍度（秒）
 * @returns true表示有效，false表示无效
 */
export function validateJWT(token: string, leeway: number = 10): boolean {
  try {
    if (!token || token.trim().length === 0) {
      return false;
    }
    
    // 尝试解析
    const jwt = parseJWT(token);
    
    // 检查是否过期
    return !isJWTExpired(jwt, leeway);
  } catch (error) {
    logger.error(TAG, `JWT验证失败: ${error}`);
    return false;
  }
}

/**
 * 从JWT令牌中提取用户信息
 * @param token JWT令牌字符串或已解析的JWT对象
 * @returns 用户信息对象
 */
export function extractUserInfo(token: string | JWTToken): ESObject {
  try {
    const jwt = typeof token === 'string' ? parseJWT(token) : token;
    const payload = jwt.payload;
    
    // 移除标准JWT字段，只返回自定义字段
    const userInfo: ESObject = {};
    const payloadKeys = Object.keys(payload);
    for (let i = 0; i < payloadKeys.length; i++) {
      const key = payloadKeys[i];
      if (key !== 'exp' && key !== 'iat' && key !== 'nbf' && key !== 'iss' && key !== 'sub' && key !== 'aud') {
        userInfo[key] = payload[key];
      }
    }
    
    return userInfo;
  } catch (error) {
    logger.error(TAG, `提取用户信息失败: ${error}`);
    return {};
  }
}
