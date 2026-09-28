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
  sub?: string;  // 主题（用户ID）
  iss?: string;  // 签发者
  aud?: string;  // 受众
  nbf?: number;  // 生效时间（秒级时间戳）
  name?: string; // 用户名
  email?: string;// 邮箱
  extra?: Map<string, string>; // 其他自定义字段
}

/**
 * JWT头部中应用会读取的标准字段。
 */
export interface JWTHeader {
  alg?: string;
  typ?: string;
  kid?: string;
  cty?: string;
}

/**
 * JWT令牌结构
 */
export interface JWTToken {
  header: JWTHeader;
  payload: JWTPayload;
  signature: string;
  raw: string;
}

/**
 * 解析JWT令牌
 * @param token JWT令牌字符串
 * @returns 解析后的JWT对象
 */
export async function parseJWT(token: string): Promise<JWTToken> {
  try {
    // JWT格式: header.payload.signature
    const parts = token.split('.');

    if (parts.length !== 3) {
      throw new Error(`Invalid JWT format: expected 3 parts, got ${parts.length}`);
    }

    const headerStr = parts[0];
    const payloadStr = parts[1];
    const signature = parts[2];

    // 解码header
    const headerJson = await base64UrlDecode(headerStr);
    const header = SafeUtils.parseObj<JWTHeader>(headerJson);

    // 解码payload
    const payloadJson = await base64UrlDecode(payloadStr);
    const payload = SafeUtils.parseObj<JWTPayload>(payloadJson);

    return {
      header,
      payload,
      signature,
      raw: token
    };
  } catch (error) {
    const errMsg = error instanceof Error ? error.message : String(error);
    logger.error(TAG, `JWT解析失败: ${errMsg}`);
    throw new Error(`JWT解析失败: ${errMsg}`);
  }
}

/**
 * 检查JWT令牌是否过期
 * @param token JWT令牌字符串或已解析的JWT对象
 * @param leeway 时间误差容忍度（秒），默认10秒
 * @returns true表示已过期，false表示未过期
 */
export async function isJWTExpired(token: string | JWTToken, leeway: number = 10): Promise<boolean> {
  try {
    const jwt = typeof token === 'string' ? await parseJWT(token) : token;
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
    const errMsg = error instanceof Error ? error.message : String(error);
    logger.error(TAG, `JWT过期检查失败: ${errMsg}`);
    // 如果解析失败，认为令牌无效（已过期）
    return true;
  }
}

/**
 * 获取JWT令牌的剩余有效时间（秒）
 * @param token JWT令牌字符串或已解析的JWT对象
 * @returns 剩余有效时间（秒），如果已过期返回0
 */
export async function getJWTRemainingTime(token: string | JWTToken): Promise<number> {
  try {
    const jwt = typeof token === 'string' ? await parseJWT(token) : token;
    const payload = jwt.payload;
    
    if (!payload.exp) {
      // 没有过期时间，认为永久有效
      return Number.MAX_SAFE_INTEGER;
    }
    
    const nowSeconds = Math.floor(Date.now() / 1000);
    const remaining = payload.exp - nowSeconds;
    
    return Math.max(0, remaining);
  } catch (error) {
    const errMsg = error instanceof Error ? error.message : String(error);
    logger.error(TAG, `获取JWT剩余时间失败: ${errMsg}`);
    return 0;
  }
}

/**
 * 验证JWT令牌的基本有效性（不验证签名）
 * @param token JWT令牌字符串
 * @param leeway 时间误差容忍度（秒）
 * @returns true表示有效，false表示无效
 */
export async function validateJWT(token: string, leeway: number = 10): Promise<boolean> {
  try {
    if (!token || token.trim().length === 0) {
      return false;
    }

    // 尝试解析
    const jwt = await parseJWT(token);

    // 检查是否过期
    return !await isJWTExpired(jwt, leeway);
  } catch (error) {
    const errMsg = error instanceof Error ? error.message : String(error);
    logger.error(TAG, `JWT验证失败: ${errMsg}`);
    return false;
  }
}

/**
 * 从JWT令牌中提取用户信息
 * @param token JWT令牌字符串或已解析的JWT对象
 * @returns 用户信息对象
 */
export async function extractUserInfo(token: string | JWTToken): Promise<JWTPayload> {
  try {
    const jwt = typeof token === 'string' ? await parseJWT(token) : token;
    return jwt.payload;
  } catch (error) {
    const errMsg = error instanceof Error ? error.message : String(error);
    logger.error(TAG, `提取用户信息失败: ${errMsg}`);
    return {} as JWTPayload;
  }
}
