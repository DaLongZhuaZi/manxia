// 文件路径: entry/src/main/ets/Framework/Utils/OnlineComicConverter.ets
// 职责: 专门用于在线漫画数据的转换工具类，独立于本地漫画的转换逻辑

import { logger } from '../../Utils/Logger';
import { DatabaseRecord } from '../Database/DatabaseTypes';
import { OnlineComicInfo, OnlineChapterInfo, OnlinePageInfo } from '../Data/DataManager';

const TAG = 'OnlineComicConverter';

/**
 * DatabaseObject 类型定义（用于数据库记录转换）
 * 使用 Record 类型替代索引签名
 */
type DatabaseObject = Record<string, Object | null | undefined>;

/**
 * 在线漫画数据转换器
 * 专门处理在线漫画的数据库记录与模型对象之间的转换
 */
export class OnlineComicConverter {
  /**
   * 将数据库记录转换为 OnlineComicInfo
   * @param record 数据库记录
   * @returns OnlineComicInfo 对象
   */
  public static convertToOnlineComicInfo(record: DatabaseRecord): OnlineComicInfo {
    const obj: DatabaseObject = record as DatabaseObject;
    
    // [调试] 输出原始数据
    logger.debug(TAG, `📋 [DB→OnlineComicInfo] 原始记录: id="${obj.id}", externalId="${obj.externalId}", title="${obj.title}"`);
    
    const info: OnlineComicInfo = {
      id: String(obj.id || ''),
      sourceId: String(obj.sourceId || '0'),
      externalId: String(obj.externalId || ''),
      title: String(obj.title || ''),
      author: String(obj.author || ''),
      description: String(obj.description || ''),
      coverUrl: String(obj.coverUrl || ''),
      tags: String(obj.tags || '').split(',').filter(t => t.trim().length > 0),
      rating: Number(obj.rating) || 0,
      lastUpdateTime: Number(obj.lastUpdateTime) || 0,
      addTime: Number(obj.addTime) || 0,
      createTime: Number(obj.createTime) || 0,
      updateTime: Number(obj.updateTime) || 0,
      sourceName: String(obj.sourceName || ''),
      sourcePkg: String(obj.sourcePkg || '')
    };
    
    logger.debug(TAG, `  ✅ [DB→OnlineComicInfo] 转换完成: id="${info.id}", externalId="${info.externalId}"`);
    
    return info;
  }

  /**
   * 将数据库记录转换为 OnlineChapterInfo
   * @param record 数据库记录
   * @returns OnlineChapterInfo 对象
   */
  public static convertToOnlineChapterInfo(record: DatabaseRecord): OnlineChapterInfo {
    const obj: DatabaseObject = record as DatabaseObject;
    
    // [调试] 输出原始数据 - 重点关注 externalId
    const rawId = obj.id;
    const rawComicId = obj.comicId;
    const rawExternalId = obj.externalId;
    const rawTitle = obj.title;
    
    logger.debug(TAG, `📋 [DB→OnlineChapterInfo] 原始记录详细信息:`);
    logger.debug(TAG, `  - id: type=${typeof rawId}, value="${rawId}"`);
    logger.debug(TAG, `  - comicId: type=${typeof rawComicId}, value="${rawComicId}"`);
    logger.debug(TAG, `  - externalId: type=${typeof rawExternalId}, value="${rawExternalId}", isNull=${rawExternalId === null}, isUndefined=${rawExternalId === undefined}`);
    logger.debug(TAG, `  - title: type=${typeof rawTitle}, value="${rawTitle}"`);
    
    // 严格的字符串转换，确保 externalId 不会丢失
    const info: OnlineChapterInfo = {
      id: String(obj.id || ''),
      comicId: String(obj.comicId || ''),
      externalId: String(obj.externalId || ''),  // 关键字段
      title: String(obj.title || ''),
      chapterNumber: Number(obj.chapterNumber) || 0,
      url: String(obj.url || ''),
      pageCount: Number(obj.pageCount) || 0,
      publishTime: Number(obj.publishTime) || 0,
      addTime: Number(obj.addTime) || 0,
      createTime: Number(obj.createTime) || 0,
      updateTime: Number(obj.updateTime) || 0,
      isDownloaded: Boolean(obj.isDownloaded) || false,
      downloadPath: obj.downloadPath ? String(obj.downloadPath) : undefined,
      index: Number(obj.index) || Number(obj.chapterNumber) || 0
    };
    
    // [调试] 输出转换后的数据
    logger.debug(TAG, `  ✅ [DB→OnlineChapterInfo] 转换完成:`);
    logger.debug(TAG, `  - id="${info.id}"`);
    logger.debug(TAG, `  - externalId="${info.externalId}" (长度: ${info.externalId.length})`);
    logger.debug(TAG, `  - title="${info.title}"`);
    
    // [验证] 如果 externalId 为空，发出警告
    if (!info.externalId || info.externalId === 'undefined' || info.externalId === 'null') {
      logger.warn(TAG, `⚠️ 警告: 章节 "${info.title}" 的 externalId 为空或无效！原始值: "${rawExternalId}"`);
    }
    
    return info;
  }

  /**
   * 将数据库记录转换为 OnlinePageInfo
   * @param record 数据库记录
   * @returns OnlinePageInfo 对象
   */
  public static convertToOnlinePageInfo(record: DatabaseRecord): OnlinePageInfo {
    const obj: DatabaseObject = record as DatabaseObject;
    
    const info: OnlinePageInfo = {
      id: String(obj.id || ''),
      chapterId: String(obj.chapterId || ''),
      pageNumber: Number(obj.pageNumber) || Number(obj.index) || 0,
      imageUrl: String(obj.imageUrl || ''),
      localPath: obj.localPath ? String(obj.localPath) : undefined,
      width: Number(obj.width) || 0,
      height: Number(obj.height) || 0,
      fileSize: Number(obj.fileSize) || 0,
      createTime: Number(obj.createTime) || 0
    };
    
    return info;
  }

  /**
   * 批量转换数据库记录为 OnlineChapterInfo 数组
   * @param records 数据库记录数组
   * @returns OnlineChapterInfo 数组
   */
  public static convertToOnlineChapterInfoArray(records: DatabaseRecord[]): OnlineChapterInfo[] {
    logger.info(TAG, `开始批量转换 ${records.length} 个在线章节记录`);
    
    const chapters: OnlineChapterInfo[] = [];
    for (let i = 0; i < records.length; i++) {
      try {
        const chapter = OnlineComicConverter.convertToOnlineChapterInfo(records[i]);
        chapters.push(chapter);
      } catch (error) {
        logger.error(TAG, `转换第 ${i + 1} 个章节记录失败: ${error}`);
      }
    }
    
    logger.info(TAG, `批量转换完成，成功转换 ${chapters.length}/${records.length} 个章节`);
    
    return chapters;
  }

  /**
   * 批量转换数据库记录为 OnlinePageInfo 数组
   * @param records 数据库记录数组
   * @returns OnlinePageInfo 数组
   */
  public static convertToOnlinePageInfoArray(records: DatabaseRecord[]): OnlinePageInfo[] {
    const pages: OnlinePageInfo[] = [];
    for (let i = 0; i < records.length; i++) {
      try {
        const page = OnlineComicConverter.convertToOnlinePageInfo(records[i]);
        pages.push(page);
      } catch (error) {
        logger.error(TAG, `转换第 ${i + 1} 个页面记录失败: ${error}`);
      }
    }
    return pages;
  }
}
