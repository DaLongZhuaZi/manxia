// 文件路径: src/main/ets/Data/SampleMangaData.ets
/**
 * 示例漫画数据（已弃用）
 * 示例数据已移除，使用手册通过 WelcomeGuideManager 初始化
 * 保留此文件以避免其他地方的引用错误
 */

import { Manga } from '../Models/MangaModels';

/**
 * 示例漫画数据（已弃用，返回空）
 * @deprecated 示例数据已移除
 */
export const SAMPLE_MANGA: Manga | null = null;

/**
 * 创建多个示例漫画数据（已弃用，返回空数组）
 * @deprecated 示例数据已移除
 */
export function createSampleMangaList(): Manga[] {
  return [];
}

/**
 * 根据ID获取示例漫画（已弃用，返回null）
 * @deprecated 示例数据已移除
 */
export function getSampleMangaById(id: string): Manga | null {
  return null;
}

/**
 * 获取默认测试漫画（已弃用，返回null）
 * @deprecated 示例数据已移除
 */
export function getDefaultTestManga(): Manga | null {
  return null;
}