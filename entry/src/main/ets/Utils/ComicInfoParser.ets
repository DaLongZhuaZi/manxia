/**
 * ComicInfo.xml解析器
 * 用于解析压缩包中的ComicInfo.xml文件，提取漫画元数据
 */

import xml from '@ohos.xml';
import util from '@ohos.util';
import { logger } from './Logger';

const TAG = 'ComicInfoParser';

/**
 * 漫画信息接口
 */
export interface ComicInfo {
  title?: string;
  series?: string;
  number?: string;
  summary?: string;
  writer?: string;
  genre?: string;
  web?: string;
  publishingStatus?: string;
  source?: string;
  year?: number;
  month?: number;
  day?: number;
  pageCount?: number;
  languageISO?: string;
  format?: string;
  blackAndWhite?: boolean;
  manga?: boolean;
}

/**
 * XML解析选项接口
 */
interface XmlParseOptions {
  supportDoctype: boolean;
  ignoreNameSpace: boolean;
  tagValueCallbackFunction: (name: string, value: string) => boolean;
  attributeValueCallbackFunction: (name: string, value: string) => boolean;
  tokenValueCallbackFunction: (eventType: xml.EventType, value: xml.ParseInfo) => boolean;
}

/**
 * 验证结果接口
 */
interface ValidationResult {
  isValid: boolean;
  errors: string[];
}

/**
 * ComicInfo.xml解析器类
 */
export class ComicInfoParser {
  private comicInfo: ComicInfo = {};
  private currentElement: string = '';
  private currentValue: string = '';

  /**
   * 解析XML字符串
   * @param xmlContent XML内容字符串
   * @returns 解析后的漫画信息
   */
  public parseXmlString(xmlContent: string): ComicInfo {
    try {
      logger.debug(TAG, '开始解析ComicInfo.xml内容');
      
      // 重置解析状态
      this.comicInfo = {};
      this.currentElement = '';
      this.currentValue = '';

      // 编码XML字符串
      const textEncoder = new util.TextEncoder();
      const arrBuffer = textEncoder.encodeInto(xmlContent);
      
      // 创建XML解析器
      const parser = new xml.XmlPullParser(arrBuffer.buffer as ArrayBuffer, 'UTF-8');
      
      // 修复未类型化对象字面量错误：使用明确的接口定义
      const options: XmlParseOptions = {
        supportDoctype: true,
        ignoreNameSpace: true,
        tagValueCallbackFunction: (name: string, value: string) => this.handleTagValue(name, value),
        attributeValueCallbackFunction: (name: string, value: string) => this.handleAttributeValue(name, value),
        tokenValueCallbackFunction: (eventType: xml.EventType, parseInfo: xml.ParseInfo) => this.handleTokenValue(eventType, parseInfo)
      };
      
      // 执行解析
      parser.parseXml(options);
      
      logger.info(TAG, 'ComicInfo.xml解析完成', JSON.stringify(this.comicInfo));
      return this.comicInfo;
      
    } catch (error) {
      logger.error(TAG, '解析ComicInfo.xml失败' + error);
      throw new Error(`XML解析失败: ${error}`);
    }
  }

  /**
   * 处理XML标签和标签值（备用方法）
   * @param name 标签名
   * @param value 标签值
   * @returns 是否继续解析
   */
  private handleTagValue(name: string, value: string): boolean {
    try {
      // 主要的XML解析逻辑已移至handleTokenValue方法
      // 这里保留作为备用，记录调试信息
      logger.debug(TAG, `tagValueCallback: name="${name}", value="${value}"`);
      return true;
    } catch (error) {
      logger.error(TAG, '处理XML标签值时出错' + error);
      return true; // 继续解析其他标签
    }
  }

  /**
   * 处理XML属性和属性值
   * @param name 属性名
   * @param value 属性值
   * @returns 是否继续解析
   */
  private handleAttributeValue(name: string, value: string): boolean {
    try {
      // ComicInfo.xml通常不使用属性，但为了完整性保留此方法
      logger.debug(TAG, `XML属性: ${name} = ${value}`);
      return true;
    } catch (error) {
      logger.error(TAG, '处理XML属性值时出错' + error);
      return true;
    }
  }

  /**
   * 处理XML事件类型和元素深度
   * @param eventType 事件类型
   * @param parseInfo 解析信息
   * @returns 是否继续解析
   */
  private handleTokenValue(eventType: xml.EventType, parseInfo: xml.ParseInfo): boolean {
    try {
      if (eventType === xml.EventType.START_TAG) {
        // 标签开始事件，保存当前标签名
        this.currentElement = parseInfo.getName();
        logger.debug(TAG, `XML标签开始: ${this.currentElement}`);
      } else if (eventType === xml.EventType.TEXT) {
        // 文本内容事件，处理标签内容
        const textContent = parseInfo.getText();
        if (textContent && textContent.trim() !== '' && this.currentElement) {
          const trimmedValue = textContent.trim();
          logger.debug(TAG, `XML标签内容: ${this.currentElement} = \`${trimmedValue}\``);
          this.mapXmlFieldToComicInfo(this.currentElement, trimmedValue);
        }
      } else if (eventType === xml.EventType.END_TAG) {
        // 标签结束事件，清空当前标签名
        logger.debug(TAG, `XML标签结束: ${parseInfo.getName()}`);
        this.currentElement = '';
      }
      return true;
    } catch (error) {
      logger.error(TAG, '处理XML事件时出错' + error);
      return true;
    }
  }

  /**
   * 将XML字段映射到ComicInfo对象
   * @param fieldName XML字段名
   * @param fieldValue XML字段值
   */
  private mapXmlFieldToComicInfo(fieldName: string, fieldValue: string): void {
    try {
      switch (fieldName.toLowerCase()) {
        case 'title':
          this.comicInfo.title = fieldValue;
          break;
        case 'series':
          this.comicInfo.series = fieldValue;
          break;
        case 'number':
          this.comicInfo.number = fieldValue;
          break;
        case 'summary':
          this.comicInfo.summary = fieldValue;
          break;
        case 'writer':
          this.comicInfo.writer = fieldValue;
          break;
        case 'genre':
          this.comicInfo.genre = fieldValue;
          break;
        case 'web':
          this.comicInfo.web = fieldValue;
          break;
        case 'publishingstatus':
        case 'publishingstatustachiyomi':
          this.comicInfo.publishingStatus = fieldValue;
          break;
        case 'source':
        case 'sourcemihon':
          this.comicInfo.source = fieldValue;
          break;
        case 'year':
          this.comicInfo.year = this.parseIntegerField(fieldValue);
          break;
        case 'month':
          this.comicInfo.month = this.parseIntegerField(fieldValue);
          break;
        case 'day':
          this.comicInfo.day = this.parseIntegerField(fieldValue);
          break;
        case 'pagecount':
          this.comicInfo.pageCount = this.parseIntegerField(fieldValue);
          break;
        case 'languageiso':
          this.comicInfo.languageISO = fieldValue;
          break;
        case 'format':
          this.comicInfo.format = fieldValue;
          break;
        case 'blackandwhite':
          this.comicInfo.blackAndWhite = this.parseBooleanField(fieldValue);
          break;
        case 'manga':
          this.comicInfo.manga = this.parseBooleanField(fieldValue);
          break;
        default:
          logger.debug(TAG, `未识别的XML字段: ${fieldName} = ${fieldValue}`);
          break;
      }
    } catch (error) {
      logger.error(TAG, `映射XML字段失败: ${fieldName}` + error);
    }
  }

  /**
   * 解析整数字段
   * @param value 字符串值
   * @returns 解析后的整数或undefined
   */
  private parseIntegerField(value: string): number | undefined {
    try {
      const parsed = parseInt(value, 10);
      return isNaN(parsed) ? undefined : parsed;
    } catch (error) {
      logger.warn(TAG, `解析整数字段失败: ${value}` + error);
      return undefined;
    }
  }

  /**
   * 解析布尔字段
   * @param value 字符串值
   * @returns 解析后的布尔值或undefined
   */
  private parseBooleanField(value: string): boolean | undefined {
    try {
      const lowerValue = value.toLowerCase();
      if (lowerValue === 'true' || lowerValue === 'yes' || lowerValue === '1') {
        return true;
      } else if (lowerValue === 'false' || lowerValue === 'no' || lowerValue === '0') {
        return false;
      }
      return undefined;
    } catch (error) {
      logger.warn(TAG, `解析布尔字段失败: ${value}` + error);
      return undefined;
    }
  }

  /**
   * 验证解析结果
   * @param comicInfo 解析后的漫画信息
   * @returns 验证结果
   */
  public static validateComicInfo(comicInfo: ComicInfo): ValidationResult {
    const errors: string[] = [];

    // 检查必需字段
    if (!comicInfo.title && !comicInfo.series) {
      errors.push('缺少标题或系列名称');
    }

    // 检查数值字段的有效性
    if (comicInfo.year !== undefined && (comicInfo.year < 1900 || comicInfo.year > 2100)) {
      errors.push('年份字段值无效');
    }

    if (comicInfo.month !== undefined && (comicInfo.month < 1 || comicInfo.month > 12)) {
      errors.push('月份字段值无效');
    }

    if (comicInfo.day !== undefined && (comicInfo.day < 1 || comicInfo.day > 31)) {
      errors.push('日期字段值无效');
    }

    if (comicInfo.pageCount !== undefined && comicInfo.pageCount < 0) {
      errors.push('页数字段值无效');
    }

    // 修复未类型化对象字面量错误：使用明确的接口定义
    const result: ValidationResult = {
      isValid: errors.length === 0,
      errors: errors
    };

    return result;
  }

  /**
   * 创建默认的ComicInfo对象
   * @param fileName 文件名，用于生成默认标题
   * @returns 默认的ComicInfo对象
   */
  public static createDefaultComicInfo(fileName: string): ComicInfo {
    // 从文件名提取标题（去除扩展名）
    const title = fileName.replace(/\.[^/.]+$/, '');
    
    return {
      title: title,
      series: title,
      format: 'Archive',
      languageISO: 'zh-CN'
    };
  }
}
