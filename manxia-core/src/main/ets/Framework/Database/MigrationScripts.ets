/**
 * 数据库迁移脚本
 * 用于升级现有数据库，添加唯一性约束和清理重复数据
 */

import { logger } from '../../Utils/Logger';
import { relationalStore } from '@kit.ArkData';

const TAG = 'DatabaseMigration';

/**
 * 唯一性索引定义
 */
export interface UniqueIndexDef {
  name: string;
  sql: string;
}

/**
 * 添加唯一性约束的迁移脚本
 * 注意：SQLite不支持直接添加约束到现有表，需要重建表
 */
export class UniqueConstraintMigration {
  readonly version: number = 2;
  readonly description: string = '添加唯一性约束防止重复数据';

  /**
   * 执行迁移
   */
  async execute(store: relationalStore.RdbStore): Promise<void> {
    logger.info(TAG, '开始执行数据库迁移：添加唯一性约束');

    try {
      // 1. 清理chapter表的重复数据
      await this.cleanDuplicateChapters(store);

      // 2. 清理page表的重复数据
      await this.cleanDuplicatePages(store);

      // 3. 清理online_chapter表的重复数据
      await this.cleanDuplicateOnlineChapters(store);

      // 4. 创建唯一性索引（如果表已经有UNIQUE约束，索引会自动创建）
      await this.createUniqueIndexes(store);

      logger.info(TAG, '数据库迁移完成：唯一性约束已添加');
    } catch (error) {
      const errMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `数据库迁移失败: ${errMsg}`);
      throw new Error(`数据库迁移失败: ${errMsg}`);
    }
  }

  /**
   * 清理chapter表的重复数据
   * 保留最新的记录，删除旧的重复记录
   */
  async cleanDuplicateChapters(store: relationalStore.RdbStore): Promise<void> {
    logger.info(TAG, '开始清理chapter表的重复数据');

    // 查找重复的章节（相同的comicId和externalId）
    const findDuplicatesSql = `
      SELECT comicId, externalId, COUNT(*) as count
      FROM chapter
      GROUP BY comicId, externalId
      HAVING COUNT(*) > 1
    `;

    const duplicates = await store.querySql(findDuplicatesSql, []);

    if (duplicates.rowCount === 0) {
      logger.info(TAG, 'chapter表没有重复数据');
      return;
    }

    logger.warn(TAG, `发现 ${duplicates.rowCount} 组重复章节`);

    // 对每组重复数据，保留createTime最新的，删除其他的
    for (let i = 0; i < duplicates.rowCount; i++) {
      if (!duplicates.goToRow(i)) {
        logger.warn(TAG, `无法定位chapter重复数据行: ${i}`);
        continue;
      }
      const comicId = duplicates.getString(duplicates.getColumnIndex('comicId'));
      const externalId = duplicates.getString(duplicates.getColumnIndex('externalId'));

      // 删除旧的重复记录，保留最新的
      const deleteSql = `
        DELETE FROM chapter
        WHERE comicId = ? AND externalId = ?
        AND id NOT IN (
          SELECT id FROM chapter
          WHERE comicId = ? AND externalId = ?
          ORDER BY createTime DESC
          LIMIT 1
        )
      `;

      await store.executeSql(deleteSql, [comicId, externalId, comicId, externalId]);
      logger.info(TAG, `已清理重复章节: comicId=${comicId}, externalId=${externalId}`);
    }

    logger.info(TAG, 'chapter表重复数据清理完成');
  }

  /**
   * 清理page表的重复数据
   */
  async cleanDuplicatePages(store: relationalStore.RdbStore): Promise<void> {
    logger.info(TAG, '开始清理page表的重复数据');

    const findDuplicatesSql = `
      SELECT chapterId, pageNumber, COUNT(*) as count
      FROM page
      GROUP BY chapterId, pageNumber
      HAVING COUNT(*) > 1
    `;

    const duplicates = await store.querySql(findDuplicatesSql, []);

    if (duplicates.rowCount === 0) {
      logger.info(TAG, 'page表没有重复数据');
      return;
    }

    logger.warn(TAG, `发现 ${duplicates.rowCount} 组重复页面`);

    for (let i = 0; i < duplicates.rowCount; i++) {
      if (!duplicates.goToRow(i)) {
        logger.warn(TAG, `无法定位page重复数据行: ${i}`);
        continue;
      }
      const chapterId = duplicates.getString(duplicates.getColumnIndex('chapterId'));
      const pageNumber = duplicates.getLong(duplicates.getColumnIndex('pageNumber'));

      const deleteSql = `
        DELETE FROM page
        WHERE chapterId = ? AND pageNumber = ?
        AND id NOT IN (
          SELECT id FROM page
          WHERE chapterId = ? AND pageNumber = ?
          ORDER BY createTime DESC
          LIMIT 1
        )
      `;

      await store.executeSql(deleteSql, [chapterId, pageNumber, chapterId, pageNumber]);
      logger.info(TAG, `已清理重复页面: chapterId=${chapterId}, pageNumber=${pageNumber}`);
    }

    logger.info(TAG, 'page表重复数据清理完成');
  }

  /**
   * 清理online_chapter表的重复数据
   */
  async cleanDuplicateOnlineChapters(store: relationalStore.RdbStore): Promise<void> {
    logger.info(TAG, '开始清理online_chapter表的重复数据');

    const findDuplicatesSql = `
      SELECT comicId, externalId, COUNT(*) as count
      FROM online_chapter
      GROUP BY comicId, externalId
      HAVING COUNT(*) > 1
    `;

    const duplicates = await store.querySql(findDuplicatesSql, []);

    if (duplicates.rowCount === 0) {
      logger.info(TAG, 'online_chapter表没有重复数据');
      return;
    }

    logger.warn(TAG, `发现 ${duplicates.rowCount} 组重复在线章节`);

    for (let i = 0; i < duplicates.rowCount; i++) {
      if (!duplicates.goToRow(i)) {
        logger.warn(TAG, `无法定位online_chapter重复数据行: ${i}`);
        continue;
      }
      const comicId = duplicates.getString(duplicates.getColumnIndex('comicId'));
      const externalId = duplicates.getString(duplicates.getColumnIndex('externalId'));

      const deleteSql = `
        DELETE FROM online_chapter
        WHERE comicId = ? AND externalId = ?
        AND id NOT IN (
          SELECT id FROM online_chapter
          WHERE comicId = ? AND externalId = ?
          ORDER BY createTime DESC
          LIMIT 1
        )
      `;

      await store.executeSql(deleteSql, [comicId, externalId, comicId, externalId]);
      logger.info(TAG, `已清理重复在线章节: comicId=${comicId}, externalId=${externalId}`);
    }

    logger.info(TAG, 'online_chapter表重复数据清理完成');
  }

  /**
   * 创建唯一性索引
   */
  async createUniqueIndexes(store: relationalStore.RdbStore): Promise<void> {
    logger.info(TAG, '开始创建唯一性索引');

    const indexes: UniqueIndexDef[] = [
      {
        name: 'idx_chapter_unique',
        sql: 'CREATE UNIQUE INDEX IF NOT EXISTS idx_chapter_unique ON chapter(comicId, externalId)'
      },
      {
        name: 'idx_page_unique',
        sql: 'CREATE UNIQUE INDEX IF NOT EXISTS idx_page_unique ON page(chapterId, pageNumber)'
      },
      {
        name: 'idx_online_comic_unique',
        sql: 'CREATE UNIQUE INDEX IF NOT EXISTS idx_online_comic_unique ON online_comic_info(sourceId, externalId)'
      },
      {
        name: 'idx_online_chapter_unique',
        sql: 'CREATE UNIQUE INDEX IF NOT EXISTS idx_online_chapter_unique ON online_chapter(comicId, externalId)'
      }
    ];

    for (let i = 0; i < indexes.length; i++) {
      const index = indexes[i];
      try {
        await store.executeSql(index.sql, []);
        logger.info(TAG, `唯一性索引创建成功: ${index.name}`);
      } catch (error) {
        const errMsg = error instanceof Error ? error.message : String(error);
        logger.error(TAG, `唯一性索引创建失败: ${index.name}, 错误: ${errMsg}`);
        // 继续创建其他索引
      }
    }

    logger.info(TAG, '唯一性索引创建完成');
  }
}

export const MIGRATION_ADD_UNIQUE_CONSTRAINTS: UniqueConstraintMigration = new UniqueConstraintMigration();

/**
 * 检查是否需要执行迁移
 */
export async function checkAndExecuteMigration(
  store: relationalStore.RdbStore,
  currentVersion: number
): Promise<void> {
  if (currentVersion < MIGRATION_ADD_UNIQUE_CONSTRAINTS.version) {
    logger.info(TAG, `检测到数据库版本过旧 (${currentVersion})，需要升级到版本 ${MIGRATION_ADD_UNIQUE_CONSTRAINTS.version}`);
    await MIGRATION_ADD_UNIQUE_CONSTRAINTS.execute(store);
  } else {
    logger.info(TAG, `数据库版本已是最新 (${currentVersion})，无需迁移`);
  }
}
