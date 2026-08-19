// 文件路径: src/main/ets/Framework/Utils/UUIDGenerator.ets
/**
 * UUID生成工具类
 * 符合ArkTS规范的类型安全设计
 * 用于生成唯一标识符，替代数字ID
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

const TAG = 'UUIDGenerator';

/**
 * UUID生成器类
 */
export class UUIDGenerator {
  private static instance: UUIDGenerator | null = null;
  private counter: number = 0;

  private constructor() {
    logger.debug(TAG, 'UUID生成器初始化');
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): UUIDGenerator {
    if (!UUIDGenerator.instance) {
      UUIDGenerator.instance = new UUIDGenerator();
    }
    return UUIDGenerator.instance;
  }

  /**
   * 生成UUID格式的字符串ID
   * 格式：xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
   */
  public generateUUID(): string {
    const timestamp = Date.now();
    const random1 = Math.floor(Math.random() * 0x10000).toString(16).padStart(4, '0');
    const random2 = Math.floor(Math.random() * 0x10000).toString(16).padStart(4, '0');
    const random3 = Math.floor(Math.random() * 0x10000).toString(16).padStart(4, '0');
    const random4 = Math.floor(Math.random() * 0x10000).toString(16).padStart(4, '0');
    const random5 = Math.floor(Math.random() * 0x10000).toString(16).padStart(4, '0');
    const random6 = Math.floor(Math.random() * 0x10000).toString(16).padStart(4, '0');
    
    const timestampHex = timestamp.toString(16).padStart(8, '0');
    
    return `${timestampHex}-${random1}-4${random2.substring(1)}-${this.generateVariantChar()}${random3.substring(1)}-${random4}${random5}${random6}`;
  }

  /**
   * 生成简化的唯一ID
   * 格式：timestamp_counter_random
   */
  public generateSimpleId(): string {
    const timestamp = Date.now();
    const counter = ++this.counter;
    const random = Math.random().toString(36).substring(2, 8);
    
    return `${timestamp}_${counter}_${random}`;
  }

  /**
   * 生成数据库友好的ID
   * 格式：prefix_timestamp_random
   */
  public generateDbId(prefix: string = 'id'): string {
    const timestamp = Date.now();
    const random = Math.random().toString(36).substring(2, 10);
    
    return `${prefix}_${timestamp}_${random}`;
  }

  /**
   * 从数字ID转换为字符串ID（用于数据迁移）
   */
  public convertLegacyId(id: number | string): string {
    if (typeof id === 'string') {
      return id;
    }
    
    // 将数字ID转换为带前缀的字符串ID
    return `legacy_${id}_${Date.now()}`;
  }

  /**
   * 验证ID格式是否有效
   */
  public isValidId(id: string): boolean {
    if (!id || typeof id !== 'string' || id.length === 0) {
      return false;
    }
    
    // 检查是否为UUID格式
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if (uuidRegex.test(id)) {
      return true;
    }
    
    // 检查是否为简化ID格式
    const simpleIdRegex = /^\d+_\d+_[a-z0-9]+$/;
    if (simpleIdRegex.test(id)) {
      return true;
    }
    
    // 检查是否为数据库ID格式
    const dbIdRegex = /^[a-z]+_\d+_[a-z0-9]+$/;
    if (dbIdRegex.test(id)) {
      return true;
    }
    
    // 检查是否为遗留ID格式
    const legacyIdRegex = /^legacy_\d+_\d+$/;
    if (legacyIdRegex.test(id)) {
      return true;
    }
    
    return false;
  }

  /**
   * 生成UUID的变体字符（8、9、A、B）
   */
  private generateVariantChar(): string {
    const variants = ['8', '9', 'a', 'b'];
    const index = Math.floor(Math.random() * variants.length);
    return variants[index] as string;
  }

  /**
   * 重置计数器（用于测试）
   */
  public resetCounter(): void {
    this.counter = 0;
    logger.debug(TAG, '计数器已重置');
  }

  /**
   * 销毁实例
   */
  public static destroyInstance(): void {
    UUIDGenerator.instance = null;
    logger.debug(TAG, 'UUID生成器实例已销毁');
  }
}

/**
 * 便捷函数：生成UUID
 */
export function generateUUID(): string {
  return UUIDGenerator.getInstance().generateUUID();
}

/**
 * 便捷函数：生成简化ID
 */
export function generateSimpleId(): string {
  return UUIDGenerator.getInstance().generateSimpleId();
}

/**
 * 便捷函数：生成数据库ID
 */
export function generateDbId(prefix: string = 'id'): string {
  return UUIDGenerator.getInstance().generateDbId(prefix);
}

/**
 * 便捷函数：转换遗留ID
 */
export function convertLegacyId(id: number | string): string {
  return UUIDGenerator.getInstance().convertLegacyId(id);
}

/**
 * 便捷函数：验证ID
 */
export function isValidId(id: string): boolean {
  return UUIDGenerator.getInstance().isValidId(id);
}