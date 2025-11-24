// 文件路径: src/main/ets/Data/SampleMangaData.ets
/**
 * 示例漫画数据
 * 用于测试和演示漫画阅读器功能
 */

import { DownloadStatus, ReadingStatus } from '../Framework/Types/StatusEnums';
import {
  Manga, 
  MangaChapter, 
  MangaPage, 
  MangaMetadata,
  ReadingProgress,
  MangaBookmark,
  ReadingSettings,
  MangaStatus,
  ImageSourceType,
  ReadingMode,
  ReadingDirection,
  DEFAULT_READING_SETTINGS
} from '../Models/MangaModels';

/**
 * 创建示例漫画页面数据
 */
function createSamplePages(chapterId: string, pageCount: number): MangaPage[] {
  const pages: MangaPage[] = [];
  
  for (let i = 0; i < pageCount; i++) {
    pages.push({
      id: `${chapterId}_page_${i}`,
      index: i,
      sourceType: ImageSourceType.RAWFILE,
      imagePath: `manga/sample/chapter_${chapterId.split('_')[1]}/page_${i + 1}.jpg`,
      width: 800,
      height: 1200,
      fileSize: 150000,
      isLoaded: false,
      imageUrl: ''
    });
  }
  
  return pages;
}

/**
 * 创建示例章节数据
 */
function createSampleChapters(): MangaChapter[] {
  const chapters: MangaChapter[] = [];
  
  for (let i = 1; i <= 5; i++) {
    chapters.push({
      id: `chapter_${i}`,
      title: `第${i}话 - 示例章节标题`,
      chapterNumber: i,
      pages: createSamplePages(`chapter_${i}`, 20),
      publishDate: new Date(2024, 0, i * 7),
      language: 'zh-CN',
      scanlationGroup: '示例汉化组',
      isDownloaded: false,
      downloadProgress: 0,
      downloadStatus: DownloadStatus.PENDING
    });
  }
  
  return chapters;
}

/**
 * 创建示例元数据
 */
function createSampleMetadata(): MangaMetadata {
  return {
    authors: ['示例作者'],
    artists: ['示例画师'],
    genres: ['冒险', '奇幻', '动作'],
    themes: ['友情', '成长', '战斗'],
    demographics: ['少年'],
    contentRating: 'PG-13',
    publicationYear: 2024,
    publisher: '示例出版社',
    serialization: '示例杂志'
  };
}

/**
 * 创建示例阅读进度
 */
function createSampleProgress(): ReadingProgress {
  return {
    currentChapterId: 'chapter_1',
    currentPageIndex: 0,
    readingStatus: ReadingStatus.READING,
    totalReadingTime: 0,
    lastReadAt: Date.now(),
    readingPercentage: 0
  };
}

/**
 * 创建示例书签
 */
function createSampleBookmarks(): MangaBookmark[] {
  return [
    {
      id: 'bookmark_1',
      chapterId: 'chapter_1',
      pageIndex: 5,
      title: '精彩场景',
      createdAt: Date.now(),
      note: '这里的战斗场面很精彩'
    }
  ];
}

/**
 * 示例漫画数据
 */
export const SAMPLE_MANGA: Manga = {
  id: 'sample_manga_001',
  title: '胆大党',
  alternativeTitles: ['DAN DA DAN', 'ダンダダン'],
  description: '故事讲述了校园女神“绫濑桃”和一个热衷外星人话题的御宅族男同学“高仓健”。绫濑桃坚信幽灵的存在，但完全不信外星人；而高仓健则相反。为了证明对方是错的，他们分别前往了灵异地点和UFO热点。结果，绫濑桃被“高速婆婆”诅咒，而高仓健则获得了外星人的力量。两人被迫卷入了一系列涉及灵异与外星人的超自然战斗中。',
  coverImagePath: 'app.media.mangabook',
  coverSourceType: ImageSourceType.RAWFILE,
  status: MangaStatus.ONGOING,
  metadata: createSampleMetadata(),
  chapters: createSampleChapters(),
  readingProgress: createSampleProgress(),
  bookmarks: createSampleBookmarks(),
  readingSettings: DEFAULT_READING_SETTINGS,
  isFavorite: true,
  addedToLibraryAt: new Date(2024, 0, 1).getTime(),
  lastUpdatedAt: Date.now(),
  sourceInfo: {
    sourceName: '本地测试源',
    sourceUrl: 'local://sample',
    sourceId: 'local_sample',
    sourceLanguage: 'zh-CN',
    requiresLogin: false,
    apiVersion: '1.0'
  }
};

/**
 * 创建多个示例漫画数据
 */
export function createSampleMangaList(): Manga[] {
  const mangaList: Manga[] = [];
  
  // 创建第一个示例漫画
  mangaList.push(SAMPLE_MANGA);
  
  // 创建第二个示例漫画
  mangaList.push({
    id: 'sample_manga_002',
    title: '舞冰的祈愿',
    alternativeTitles: ['金牌得主', 'Medalist', 'メダリスト'],
    description: '故事讲述了被放弃的少女“结束祈”，与梦想破灭的青年“明浦路司”相遇。司成为了祈的教练，两人组成搭档，共同向花样滑冰的世界顶峰发起挑战。',
    coverImagePath: 'app.media.mangabook',
    coverSourceType: SAMPLE_MANGA.coverSourceType,
    status: MangaStatus.COMPLETED,
    metadata: {
      authors: ['示例作者2'],
      artists: createSampleMetadata().artists,
      genres: ['校园', '恋爱', '日常'],
      themes: ['青春', '友情', '恋爱'],
      demographics: createSampleMetadata().demographics,
      contentRating: createSampleMetadata().contentRating,
      publicationYear: createSampleMetadata().publicationYear,
      publisher: createSampleMetadata().publisher,
      serialization: createSampleMetadata().serialization
    },
    chapters: createSampleChapters().map(chapter => ({
      id: `manga2_${chapter.id}`,
      title: chapter.title,
      chapterNumber: chapter.chapterNumber,
      pages: chapter.pages.map(page => ({
        id: `manga2_${page.id}`,
        index: page.index,
        sourceType: page.sourceType,
        imagePath: page.imagePath.replace('sample', 'sample2'),
        width: page.width,
        height: page.height,
        fileSize: page.fileSize,
        isLoaded: page.isLoaded,
        imageUrl: page.imageUrl
      } as MangaPage)),
      publishDate: chapter.publishDate,
      language: chapter.language,
      scanlationGroup: chapter.scanlationGroup,
      isDownloaded: chapter.isDownloaded,
      downloadProgress: chapter.downloadProgress
    } as MangaChapter)),
    readingProgress: {
      currentChapterId: 'manga2_chapter_1',
      currentPageIndex: createSampleProgress().currentPageIndex,
      totalReadingTime: createSampleProgress().totalReadingTime,
      lastReadAt: createSampleProgress().lastReadAt,
      readingPercentage: createSampleProgress().readingPercentage,
      readingStatus: ReadingStatus.READING
    },
    bookmarks: SAMPLE_MANGA.bookmarks,
    readingSettings: SAMPLE_MANGA.readingSettings,
    isFavorite: false,
    addedToLibraryAt: SAMPLE_MANGA.addedToLibraryAt,
    lastUpdatedAt: SAMPLE_MANGA.lastUpdatedAt,
    sourceInfo: SAMPLE_MANGA.sourceInfo
  });
  
  // 创建第三个示例漫画
  mangaList.push({
    id: 'sample_manga_003',
    title: '示例漫画：科幻未来',
    alternativeTitles: ['Sample Manga: Sci-Fi Future'],
    description: '在遥远的未来，人类与机器人共存的世界中，一个年轻的工程师发现了改变世界的秘密。',
    coverImagePath: 'app.media.mangabook',
    coverSourceType: SAMPLE_MANGA.coverSourceType,
    status: MangaStatus.HIATUS,
    metadata: {
      authors: ['示例作者3'],
      artists: createSampleMetadata().artists,
      genres: ['科幻', '机甲', '悬疑'],
      themes: ['未来', '科技', '人性'],
      demographics: createSampleMetadata().demographics,
      contentRating: createSampleMetadata().contentRating,
      publicationYear: createSampleMetadata().publicationYear,
      publisher: createSampleMetadata().publisher,
      serialization: createSampleMetadata().serialization
    },
    chapters: createSampleChapters().slice(0, 3).map(chapter => ({ // 只有3章
      id: `manga3_${chapter.id}`,
      title: chapter.title,
      chapterNumber: chapter.chapterNumber,
      pages: chapter.pages.map(page => ({
        id: `manga3_${page.id}`,
        index: page.index,
        sourceType: page.sourceType,
        imagePath: page.imagePath.replace('sample', 'sample3'),
        width: page.width,
        height: page.height,
        fileSize: page.fileSize,
        isLoaded: page.isLoaded,
        imageUrl: page.imageUrl
      } as MangaPage)),
      publishDate: chapter.publishDate,
      language: chapter.language,
      scanlationGroup: chapter.scanlationGroup,
      isDownloaded: chapter.isDownloaded,
      downloadProgress: chapter.downloadProgress
    } as MangaChapter)),
    readingProgress: {
      currentChapterId: 'manga3_chapter_1',
      currentPageIndex: createSampleProgress().currentPageIndex,
      totalReadingTime: createSampleProgress().totalReadingTime,
      lastReadAt: createSampleProgress().lastReadAt,
      readingPercentage: createSampleProgress().readingPercentage,
      readingStatus: ReadingStatus.READING
    },
    bookmarks: SAMPLE_MANGA.bookmarks,
    readingSettings: SAMPLE_MANGA.readingSettings,
    isFavorite: true,
    addedToLibraryAt: SAMPLE_MANGA.addedToLibraryAt,
    lastUpdatedAt: SAMPLE_MANGA.lastUpdatedAt,
    sourceInfo: SAMPLE_MANGA.sourceInfo
  });
  
  return mangaList;
}

/**
 * 根据ID获取示例漫画
 */
export function getSampleMangaById(id: string): Manga | null {
  const mangaList = createSampleMangaList();
  return mangaList.find(manga => manga.id === id) || null;
}

/**
 * 获取默认测试漫画（用于快速测试）
 */
export function getDefaultTestManga(): Manga {
  return SAMPLE_MANGA;
}