/**
 * 加密工具类
 * 提供HMAC-SHA256等加密功能，用于API请求签名
 */

import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { logger } from './Logger';

const TAG = 'CryptoUtils';

/**
 * 将字符串转换为Uint8Array
 */
function stringToUint8Array(str: string): Uint8Array {
  const encoder = new util.TextEncoder();
  return encoder.encodeInto(str);
}

/**
 * 将Uint8Array转换为十六进制字符串
 */
function uint8ArrayToHex(arr: Uint8Array): string {
  const hexTable: string = '0123456789abcdef';
  let result: string = '';
  for (let i: number = 0; i < arr.length; i++) {
    const value: number = arr[i];
    result += hexTable.charAt(value >>> 4);
    result += hexTable.charAt(value & 0x0f);
  }
  return result;
}

/**
 * HMAC-SHA256加密
 * @param key 密钥
 * @param data 要加密的数据
 * @returns 十六进制格式的签名字符串
 */
export async function hmacSHA256(key: string, data: string): Promise<string> {
  try {
    // 创建HMAC生成器
    const macAlgName = 'SHA256';
    const mac = cryptoFramework.createMac(macAlgName);
    
    // 将密钥转换为SymKey
    const keyBlob: cryptoFramework.DataBlob = {
      data: stringToUint8Array(key)
    };
    const symKeyGenerator = cryptoFramework.createSymKeyGenerator('HMAC');
    const symKey = await symKeyGenerator.convertKey(keyBlob);
    
    // 初始化MAC
    await mac.init(symKey);
    
    // 更新数据
    const dataBlob: cryptoFramework.DataBlob = {
      data: stringToUint8Array(data)
    };
    await mac.update(dataBlob);
    
    // 生成MAC
    const macResult = await mac.doFinal();
    
    // 转换为十六进制字符串
    return uint8ArrayToHex(macResult.data);
  } catch (error) {
    logger.error(TAG, `HMAC-SHA256加密失败: ${error}`);
    throw new Error(String(error));
  }
}

/**
 * 生成随机字符串（用于nonce）
 * @param length 字符串长度
 * @returns 随机字符串
 */
export function generateRandomString(length: number): string {
  const allowedChars: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let result: string = '';
  for (let i: number = 0; i < length; i++) {
    const randomIndex: number = Math.floor(Math.random() * allowedChars.length);
    result += allowedChars.charAt(randomIndex);
  }
  return result;
}

/**
 * Base64 URL安全解码
 * @param str Base64编码的字符串
 * @returns 解码后的字符串
 */
export async function base64UrlDecode(str: string): Promise<string> {
  try {
    // 替换URL安全字符
    let base64: string = str.replace(/-/g, '+').replace(/_/g, '/');

    // 添加填充
    const padding: number = base64.length % 4;
    if (padding > 0) {
      base64 += '='.repeat(4 - padding);
    }

    // 解码 - 使用 Base64Helper 实例
    const base64Helper: util.Base64Helper = new util.Base64Helper();
    const decodedArray: Uint8Array = await base64Helper.decode(base64);
    const textDecoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    return textDecoder.decodeToString(decodedArray);
  } catch (error) {
    logger.error(TAG, `Base64 URL解码失败: ${error}`);
    throw new Error(String(error));
  }
}

/**
 * Base64编码
 * @param str 要编码的字符串
 * @returns Base64编码后的字符串
 */
export function base64Encode(str: string): string {
  try {
    const uint8Array: Uint8Array = stringToUint8Array(str);
    const base64Helper: util.Base64Helper = new util.Base64Helper();
    return base64Helper.encodeToStringSync(uint8Array);
  } catch (error) {
    logger.error(TAG, `Base64编码失败: ${error}`);
    throw new Error(String(error));
  }
}

/**
 * MD5哈希（如果需要）
 * 注意：HarmonyOS的crypto框架可能不直接支持MD5，这里提供接口
 */
export async function md5Hash(data: string): Promise<string> {
  try {
    const md = cryptoFramework.createMd('MD5');
    const dataBlob: cryptoFramework.DataBlob = {
      data: stringToUint8Array(data)
    };
    await md.update(dataBlob);
    const result = await md.digest();
    return uint8ArrayToHex(result.data);
  } catch (error) {
    logger.error(TAG, `MD5哈希失败: ${error}`);
    throw new Error(String(error));
  }
}

/**
 * SHA-256 hash for stable, non-secret identifiers.
 */
export async function sha256Hash(data: string): Promise<string> {
  try {
    const md = cryptoFramework.createMd('SHA256');
    const dataBlob: cryptoFramework.DataBlob = {
      data: stringToUint8Array(data)
    };
    await md.update(dataBlob);
    const result = await md.digest();
    return uint8ArrayToHex(result.data);
  } catch (error) {
    logger.error(TAG, `SHA-256哈希失败: ${String(error)}`);
    throw new Error(String(error));
  }
}

/**
 * 生成加密安全的随机字节
 * @param length 字节数
 * @returns 随机字节数组
 */
export async function generateRandomBytes(length: number): Promise<Uint8Array> {
  const rand = cryptoFramework.createRandom();
  const randomData = await rand.generateRandom(length);
  return randomData.data;
}

/**
 * 生成 AES-256 对称密钥
 * @returns SymKey 对象
 */
export async function generateAes256Key(): Promise<cryptoFramework.SymKey> {
  const keyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
  return await keyGenerator.generateSymKey();
}

/**
 * 将 SymKey 导出为 Base64 字符串（用于持久化存储）
 * @param key 对称密钥
 * @returns Base64 编码的密钥字符串
 */
export async function exportSymKeyToBase64(key: cryptoFramework.SymKey): Promise<string> {
  const keyBlob = key.getEncoded();
  const base64Helper = new util.Base64Helper();
  return await base64Helper.encodeToString(keyBlob.data);
}

/**
 * 从 Base64 字符串导入 SymKey
 * @param base64Key Base64 编码的密钥字符串
 * @returns SymKey 对象
 */
export async function importSymKeyFromBase64(base64Key: string): Promise<cryptoFramework.SymKey> {
  const base64Helper = new util.Base64Helper();
  const keyBytes: Uint8Array = await base64Helper.decode(base64Key);
  const keyBlob: cryptoFramework.DataBlob = { data: keyBytes };
  const keyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
  return await keyGenerator.convertKey(keyBlob);
}

/**
 * AES-256-GCM 加密
 * 输出格式: Base64( IV[12字节] + 密文 + AuthTag[16字节] )
 * @param plaintext 明文字符串
 * @param key AES-256 对称密钥
 * @returns Base64 编码的密文
 */
export async function aes256GcmEncrypt(plaintext: string, key: cryptoFramework.SymKey): Promise<string> {
  try {
    const ivBytes: Uint8Array = await generateRandomBytes(12);
    const gcmParams: cryptoFramework.GcmParamsSpec = {
      algName: 'GcmParamsSpec',
      iv: { data: ivBytes },
      aad: { data: new Uint8Array(0) },
      authTag: { data: new Uint8Array(0) }
    };
    const cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, key, gcmParams);
    const plainData: cryptoFramework.DataBlob = { data: stringToUint8Array(plaintext) };
    const encryptedResult = await cipher.doFinal(plainData);
    const cipherBytes: Uint8Array = encryptedResult.data;
    // 拼接 IV + 密文(含Tag)
    const combined: Uint8Array = new Uint8Array(ivBytes.length + cipherBytes.length);
    combined.set(ivBytes, 0);
    combined.set(cipherBytes, ivBytes.length);
    const base64Helper = new util.Base64Helper();
    return await base64Helper.encodeToString(combined);
  } catch (error) {
    logger.error(TAG, `AES-256-GCM加密失败: ${error}`);
    throw new Error(String(error));
  }
}

/**
 * AES-256-GCM 解密
 * 输入格式: Base64( IV[12字节] + 密文 + AuthTag[16字节] )
 * @param ciphertextBase64 Base64 编码的密文
 * @param key AES-256 对称密钥
 * @returns 解密后的明文字符串
 */
export async function aes256GcmDecrypt(ciphertextBase64: string, key: cryptoFramework.SymKey): Promise<string> {
  try {
    const base64Helper = new util.Base64Helper();
    const combined: Uint8Array = await base64Helper.decode(ciphertextBase64);
    if (combined.length < 28) {
      throw new Error('密文数据过短');
    }
    const ivBytes: Uint8Array = combined.slice(0, 12);
    // GCM auth tag 固定 16 字节，位于密文末尾
    const authTag: Uint8Array = combined.slice(combined.length - 16);
    const cipherOnly: Uint8Array = combined.slice(12, combined.length - 16);
    const gcmParams: cryptoFramework.GcmParamsSpec = {
      algName: 'GcmParamsSpec',
      iv: { data: ivBytes },
      aad: { data: new Uint8Array(0) },
      authTag: { data: authTag }
    };
    const cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
    await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, key, gcmParams);
    const cipherData: cryptoFramework.DataBlob = { data: cipherOnly };
    const decryptedResult = await cipher.doFinal(cipherData);
    const textDecoder = new util.TextDecoder('utf-8');
    return textDecoder.decodeToString(decryptedResult.data);
  } catch (error) {
    logger.error(TAG, `AES-256-GCM解密失败: ${error}`);
    throw new Error(String(error));
  }
}
