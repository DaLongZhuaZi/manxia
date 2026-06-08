import { MangaPage } from '../Models/MangaModels';

/**
 * 条漫多章节数据项类型
 * 用于区分普通页面和章节分隔项
 */
export interface WebtoonDataItem {
  type: 'page' | 'chapter_divider';
  page?: MangaPage;
  chapterId?: string;
  chapterTitle?: string;
  direction?: 'prev' | 'next';
  pageIndex?: number;
  globalIndex?: number;
}

/**
 * 章节边界信息
 */
export interface ChapterBoundary {
  chapterId: string;
  startIndex: number;
  endIndex: number;
  pageCount: number;
}

/**
 * 条漫页面引用信息（多章节统一索引）
 */
export interface WebtoonPageRef {
  page: MangaPage;
  chapterId: string;
  chapterPageIndex: number;
  itemIndex: number;
  orderIndex: number;
}
