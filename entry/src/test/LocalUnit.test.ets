import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { ChapterOrderRuleSorter, ChapterRuleSortResult } from '../main/ets/Framework/Services/ChapterOrderRuleSorter';
import { TxtTocRule } from '../main/ets/Framework/Novel/NovelTxtTocRuleManager';
import { DEFAULT_TXT_TOC_RULES, TxtTocRule as SettingsTxtTocRule } from 'manxia_core/src/main/ets/Framework/Novel/NovelSettingsManager';
import { UnifiedChapter, UnifiedContentType } from 'manxia_core/src/main/ets/Models/UnifiedContentModels';
import { getGlobalSearchFlowMonitor, GlobalSearchFlowMonitor } from 'manxia_source_engine/src/main/ets/Framework/Search/GlobalSearchFlowMonitor';
import {
  GlobalSearchFlowEvent,
  GlobalSearchFlowEventType,
  GlobalSearchFlowSessionInfo,
  GlobalSearchFlowSeverity,
  GlobalSearchFlowSnapshot,
  GlobalSearchFlowSummary
} from 'manxia_source_engine/src/main/ets/Framework/Search/GlobalSearchFlowTypes';
import {
  buildGlobalSearchCacheKey,
  createGlobalSearchCacheData,
  GlobalSearchCacheData,
  GlobalSearchCachedComicInfo
} from 'manxia_source_engine/src/main/ets/Framework/Search/GlobalSearchCacheBridge';
import { getImportFlowMonitor, ImportFlowMonitor } from 'manxia_core/src/main/ets/Framework/Import/ImportFlowMonitor';
import {
  ImportFlowContentType,
  ImportFlowEntrySource,
  ImportFlowEvent,
  ImportFlowEventType,
  ImportFlowSessionInfo,
  ImportFlowSeverity,
  ImportFlowSnapshot,
  ImportFlowSummary
} from 'manxia_core/src/main/ets/Framework/Import/ImportFlowTypes';
import { getImportArchiveParseCache, ImportArchiveParseCache } from '../main/ets/Framework/Import/ImportArchiveParseCache';
import { getImportDuplicateDetectionCache, ImportDuplicateDetectionCache } from '../main/ets/Framework/Import/ImportDuplicateDetectionCache';
import { ExistingMangaCandidate } from '../main/ets/Framework/Components/MangaImportDialog';
import { getDownloadCacheFlowMonitor, DownloadCacheFlowMonitor } from 'manxia_network/src/main/ets/Framework/Download/DownloadCacheFlowMonitor';
import {
  DownloadCacheContentType,
  DownloadCacheEntrySource,
  DownloadCacheFlowEvent,
  DownloadCacheFlowEventType,
  DownloadCacheFlowSessionInfo,
  DownloadCacheFlowSeverity,
  DownloadCacheFlowSnapshot,
  DownloadCacheFlowStage,
  DownloadCacheFlowSummary
} from 'manxia_network/src/main/ets/Framework/Download/DownloadCacheFlowTypes';
import { getDownloadCacheFailureTtlCache, DownloadCacheFailureTtlCache } from 'manxia_network/src/main/ets/Framework/Download/DownloadCacheFailureTtlCache';
import {
  DownloadCacheLimiterPermit,
  DownloadCacheSourceLimiter,
  getDownloadCacheSourceLimiter
} from 'manxia_network/src/main/ets/Framework/Download/DownloadCacheSourceLimiter';
import {
  CacheStatusIncrementalChapter,
  CacheStatusIncrementalStats,
  CacheStatusIncrementalStore,
  getCacheStatusIncrementalStore
} from '../main/ets/Framework/Services/CacheStatusIncrementalStore';
import { BasicDataSource, BasicDataSourceStableUpdateResult } from '../main/ets/Utils/BasicDataSource';
import { getHomeLoadFlowMonitor, HomeLoadFlowMonitor } from '../main/ets/Framework/Home/HomeLoadFlowMonitor';
import {
  HomeLoadFlowEntryReason,
  HomeLoadFlowEvent,
  HomeLoadFlowEventType,
  HomeLoadFlowPrimaryTab,
  HomeLoadFlowSessionInfo,
  HomeLoadFlowSeverity,
  HomeLoadFlowSnapshot,
  HomeLoadFlowStage,
  HomeLoadFlowSummary
} from '../main/ets/Framework/Home/HomeLoadFlowTypes';
import { getHomeCoverFailureTtlCache, HomeCoverFailureTtlCache } from '../main/ets/Framework/Home/HomeCoverFailureTtlCache';
import { HomeCoverPreloadResultProcessor } from '../main/ets/Framework/Home/HomeCoverPreloadResultProcessor';
import {
  buildMangaImageRetryKey,
  MangaImageRetryCoordinator,
  MangaImageRetryDecision,
  MangaImageRetryPhase
} from '../main/ets/Framework/Reader/MangaImageRetryCoordinator';
import {
  buildMangaAssetRequestKey,
  MangaAssetLoadReason,
  MangaAssetLoadRequest,
  MangaAssetRetryMode
} from '../main/ets/Framework/Reader/MangaAssetTypes';
import {
  MangaAssetRequestContext,
  MangaAssetRequestFactory
} from '../main/ets/Framework/Reader/MangaAssetRequestFactory';
import { DEFAULT_READING_SETTINGS, ImageSourceType, MangaChapter, MangaPage } from 'manxia_core/src/main/ets/Models/MangaModels';
import { MangaPageLoadResolver, MangaPageResolveContext } from '../main/ets/components/MangaPageLoadResolver';
import { MangaImageFitLayout, MangaImageFitMode, MangaImageFitPlanner, resolveMangaImageFitMode } from '../main/ets/components/MangaImageFitPlanner';
import { CoverPreloadResult } from '../main/ets/Framework/Image/CoverImageManager';
import { TransferredBookValidation } from '../main/ets/Framework/Services/TransferredBookValidation';
import {
  ContinuationReadingSettings,
  ContinuationTransferFile,
  ContinuationTransferManifest,
  ContinuationTransferMode,
  ContinuationTransferRequest,
  normalizeContinuationReadingSettings,
  resolveContinuationTransferMode
} from '../main/ets/Framework/Distributed/ContinuationReadingTypes';
import {
  isContinuationManifestCompatible,
  normalizeContinuationPackagePath
} from '../main/ets/Framework/Distributed/ContinuationTransferManifestValidator';
import {
  MangaTransferBundle,
  RemoteComicMetadata
} from '../main/ets/Framework/Distributed/MangaTransferTypes';
import { EBook, EBookChapter, EBookFormat, EBookMetadata } from 'manxia_core/src/main/ets/Models/EBookModels';
import { DetectedChapterInfo, ParsedArchiveStructure as CompressionParsedStructure } from 'manxia_core/src/main/ets/Utils/CompressionUtils';
import { WebtoonPageRef } from '../main/ets/components/MangaWebtoonTypes';

function createTestChapter(id: string, title: string, index: number): UnifiedChapter {
  const chapter: UnifiedChapter = {
    id: id,
    title: title,
    index: index,
    isRead: false,
    isDownloaded: false,
    isBookmarked: false,
    originalData: new Object(),
    originalType: UnifiedContentType.NOVEL
  };
  return chapter;
}

function createMangaAssetTestPage(): MangaPage {
  const page: MangaPage = {
    id: 'page-1',
    index: 0,
    sourceType: ImageSourceType.LOCAL,
    imagePath: '/data/page-1.jpg',
    imageUrl: 'https://example.test/page-1.jpg',
    localPath: '/data/page-1.jpg',
    isLoaded: false,
    priority: 1
  };
  return page;
}

function createTestRule(id: string, pattern: string, serialNumber: number): TxtTocRule {
  const rule: TxtTocRule = {
    id: id,
    name: `规则${id}`,
    rule: pattern,
    example: '',
    serialNumber: serialNumber,
    enabled: true,
    createTime: 0,
    updateTime: 0
  };
  return rule;
}

function sortTitles(titles: string[]): string[] {
  const chapters: UnifiedChapter[] = [];
  for (let i = 0; i < titles.length; i++) {
    chapters.push(createTestChapter(`c${i}`, titles[i], i));
  }
  const rules: TxtTocRule[] = [
    createTestRule('chapter', '^(?:第[\\d０-９零〇一二两三四五六七八九十百千万萬壹贰叁肆伍陆柒捌玖拾佰仟壱弐参]+(?:章|話|话)|[Cc]hapter\\s*(?:\\d+|[IVXLCDMivxlcdm]+)|(?:[Tt]ank(?:o|ō)bon|[Dd]oujinshi|[Mm]anhwa|[Mm]anhua|[Ww]ebtoon|[Mm]anga|[Cc]omic)\\s*(?:\\d+|[IVXLCDMivxlcdm]+)|(?:제\\s*)?[\\d０-９]+화|(?:Photo Set|写真集|화보|Gravure|Cosplay|Look Book)\\s*[\\d０-９]+|封面|Cover|Preview|序章|楔子|前言|终章|後記|后记|尾声|番外|番外編|외전|Translator Notes|Color Pages).{0,40}$', 0)
  ];
  const sorter = new ChapterOrderRuleSorter();
  const result: ChapterRuleSortResult = sorter.sortByTxtRules(chapters, rules, '');
  const sortedTitles: string[] = [];
  for (let i = 0; i < result.orderedChapters.length; i++) {
    sortedTitles.push(result.orderedChapters[i].title);
  }
  return sortedTitles;
}

function defaultTxtTocRuleMatches(ruleName: string, title: string): boolean {
  for (let i = 0; i < DEFAULT_TXT_TOC_RULES.length; i++) {
    const rule: SettingsTxtTocRule = DEFAULT_TXT_TOC_RULES[i];
    if (rule.name !== ruleName) {
      continue;
    }
    const pattern = new RegExp(rule.pattern);
    return pattern.test(title);
  }
  return false;
}

class TestDataChangeListener implements DataChangeListener {
  public reloadCount: number = 0;
  public addCount: number = 0;
  public deleteCount: number = 0;
  public changeCount: number = 0;
  public moveCount: number = 0;

  public onDataReloaded(): void {
    this.reloadCount = this.reloadCount + 1;
  }

  public onDataAdded(_index: number): void {
    this.addCount = this.addCount + 1;
  }

  public onDataMoved(_from: number, _to: number): void {
    this.moveCount = this.moveCount + 1;
  }

  public onDataDeleted(_index: number): void {
    this.deleteCount = this.deleteCount + 1;
  }

  public onDataChanged(_index: number): void {
    this.changeCount = this.changeCount + 1;
  }

  public onDatasetChange(_operations: DataOperation[]): void {
    this.reloadCount = this.reloadCount + 1;
  }

  public onDataAdd(_index: number): void {
    this.addCount = this.addCount + 1;
  }

  public onDataDelete(_index: number): void {
    this.deleteCount = this.deleteCount + 1;
  }

  public onDataChange(_index: number): void {
    this.changeCount = this.changeCount + 1;
  }

  public onDataMove(_from: number, _to: number): void {
    this.moveCount = this.moveCount + 1;
  }
}

class TestStableItem {
  public id: string = '';
  public title: string = '';

  public constructor(id: string, title: string) {
    this.id = id;
    this.title = title;
  }
}

export default function localUnitTest() {
  describe('localUnitTest', () => {
    // Defines a test suite. Two parameters are supported: test suite name and test suite function.
    beforeAll(() => {
      // Presets an action, which is performed only once before all test cases of the test suite start.
      // This API supports only one parameter: preset action function.
    });
    beforeEach(() => {
      // Presets an action, which is performed before each unit test case starts.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: preset action function.
    });
    afterEach(() => {
      // Presets a clear action, which is performed after each unit test case ends.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: clear action function.
    });
    afterAll(() => {
      // Presets a clear action, which is performed after all test cases of the test suite end.
      // This API supports only one parameter: clear action function.
    });
    it('assertContain', 0, () => {
      // Defines a test case. This API supports three parameters: test case name, filter parameter, and test case function.
      let a = 'abc';
      let b = 'b';
      // Defines a variety of assertion methods, which are used to declare expected boolean conditions.
      expect(a).assertContain(b);
      expect(a).assertEqual(a);
    });

    it('chapterOrderRuleSorterChineseNumbers', 0, () => {
      const sorted = sortTitles(['第十章 结束', '第二章 中段', '第一章 开始']);
      expect(sorted.join('|')).assertEqual('第一章 开始|第二章 中段|第十章 结束');
    });

    it('chapterOrderRuleSorterArabicAndEnglish', 0, () => {
      const sorted = sortTitles(['Chapter 12 Tail', '第3章 中文', 'Chapter 1 Start']);
      expect(sorted.join('|')).assertEqual('Chapter 1 Start|第3章 中文|Chapter 12 Tail');
    });

    it('chapterOrderRuleSorterPrefaceAndExtra', 0, () => {
      const sorted = sortTitles(['番外 2', '第二章 正文', '序章 开场', '第一章 初见']);
      expect(sorted.join('|')).assertEqual('序章 开场|第一章 初见|第二章 正文|番外 2');
    });

    it('chapterOrderRuleSorterKeepsDuplicateOrderStable', 0, () => {
      const sorted = sortTitles(['第二章 乙', '第二章 甲', '第一章']);
      expect(sorted.join('|')).assertEqual('第一章|第二章 乙|第二章 甲');
    });

    it('chapterOrderRuleSorterNoMatchKeepsOrder', 0, () => {
      const chapters: UnifiedChapter[] = [
        createTestChapter('a', '苹果', 0),
        createTestChapter('b', '香蕉', 1)
      ];
      const rules: TxtTocRule[] = [
        createTestRule('none', '^不会匹配$', 0)
      ];
      const sorter = new ChapterOrderRuleSorter();
      const result: ChapterRuleSortResult = sorter.sortByTxtRules(chapters, rules, '');
      expect(result.orderedChapters[0].title).assertEqual('苹果');
      expect(result.orderedChapters[1].title).assertEqual('香蕉');
      expect(result.movedCount).assertEqual(0);
    });

    it('chapterOrderRuleSorterFullWidthAndJapanese', 0, () => {
      const sorted = sortTitles(['第１２話 後編', '第２話 出会い', '第1話 はじまり']);
      expect(sorted.join('|')).assertEqual('第1話 はじまり|第２話 出会い|第１２話 後編');
    });

    it('chapterOrderRuleSorterKoreanWebtoonTerms', 0, () => {
      const sorted = sortTitles(['제10화', '외전 특별편', '제2화']);
      expect(sorted.join('|')).assertEqual('제2화|제10화|외전 특별편');
    });

    it('chapterOrderRuleSorterEnglishRomanNumbers', 0, () => {
      const sorted = sortTitles(['Chapter IV', 'Chapter II', 'Chapter X']);
      expect(sorted.join('|')).assertEqual('Chapter II|Chapter IV|Chapter X');
    });

    it('chapterOrderRuleSorterPhotoBookTerms', 0, () => {
      const sorted = sortTitles(['Photo Set 12', '写真集 2', '화보 1']);
      expect(sorted.join('|')).assertEqual('화보 1|写真集 2|Photo Set 12');
    });

    it('chapterOrderRuleSorterMangaReleaseTerms', 0, () => {
      const sorted = sortTitles(['Tankobon 10', 'Manhwa 2', 'Doujinshi 1']);
      expect(sorted.join('|')).assertEqual('Doujinshi 1|Manhwa 2|Tankobon 10');
    });

    it('chapterOrderRuleSorterPhotoReleaseTerms', 0, () => {
      const sorted = sortTitles(['Gravure 12', 'Cosplay 3', 'Look Book 1']);
      expect(sorted.join('|')).assertEqual('Look Book 1|Cosplay 3|Gravure 12');
    });

    it('chapterOrderRuleSorterCoverAndNotesPosition', 0, () => {
      const sorted = sortTitles(['Translator Notes', 'Chapter 1', 'Cover']);
      expect(sorted.join('|')).assertEqual('Cover|Chapter 1|Translator Notes');
    });

    it('defaultTxtTocRulesMultilingualReleaseTerms', 0, () => {
      expect(defaultTxtTocRuleMatches('多语言目录(漫画发布术语)', 'Tankobon Vol.2 Bonus')).assertTrue();
      expect(defaultTxtTocRuleMatches('多语言目录(漫画发布术语)', 'Translator Notes')).assertTrue();
      expect(defaultTxtTocRuleMatches('多语言目录(漫画发布术语)', '同人誌 特典')).assertTrue();
      expect(defaultTxtTocRuleMatches('多语言目录(漫画发布术语)', '총집편')).assertTrue();
      expect(defaultTxtTocRuleMatches('漫画写真目录(写真发布术语)', 'Gravure Set 03')).assertTrue();
      expect(defaultTxtTocRuleMatches('漫画写真目录(写真发布术语)', 'デジタル写真集 Vol.2')).assertTrue();
      expect(defaultTxtTocRuleMatches('漫画写真目录(写真发布术语)', '포트폴리오 4')).assertTrue();
    });

    it('globalSearchFlowMonitorRecordsSnapshotBuckets', 0, () => {
      const monitor: GlobalSearchFlowMonitor = getGlobalSearchFlowMonitor();
      const sessionId: string = monitor.createSessionId('unit_global_search');
      const info: GlobalSearchFlowSessionInfo = new GlobalSearchFlowSessionInfo();
      info.sessionId = sessionId;
      info.keyword = 'flow';
      info.contentType = 'all';
      info.sourceType = 'all';
      info.selectedMangaSourceCount = 1;
      info.selectedNovelSourceCount = 1;
      monitor.ensureSession(info);

      const slowEvent: GlobalSearchFlowEvent = monitor.createEvent(sessionId, GlobalSearchFlowEventType.TASK_SUCCEEDED, 'unit_slow');
      slowEvent.taskKind = 'local';
      slowEvent.elapsedMs = 1500;
      slowEvent.itemCount = 2;
      monitor.record(slowEvent);

      const failedEvent: GlobalSearchFlowEvent = monitor.createEvent(sessionId, GlobalSearchFlowEventType.TASK_FAILED, 'unit_failed');
      failedEvent.success = false;
      failedEvent.severity = GlobalSearchFlowSeverity.ERROR;
      failedEvent.errorMessage = 'unit failure';
      monitor.record(failedEvent);
      monitor.endSession(sessionId, 'unit_done');

      const snapshot: GlobalSearchFlowSnapshot = monitor.createSnapshot();
      const hasFailedEvent: boolean = snapshot.failedEvents.some((event: GlobalSearchFlowEvent): boolean => event.sessionId === sessionId);
      const hasSlowEvent: boolean = snapshot.slowEvents.some((event: GlobalSearchFlowEvent): boolean => event.sessionId === sessionId);
      const hasEndedSession: boolean = snapshot.recentSessions.some((summary: GlobalSearchFlowSummary): boolean => summary.sessionId === sessionId && summary.endReason === 'unit_done');
      expect(hasFailedEvent).assertTrue();
      expect(hasSlowEvent).assertTrue();
      expect(hasEndedSession).assertTrue();
      expect(snapshot.recentEventCount <= 240).assertTrue();
    });

    it('globalSearchCacheBridgeKeepsSessionIdAndStableKey', 0, () => {
      const keyA: string = buildGlobalSearchCacheKey(12, '  Flow Test  ');
      const keyB: string = buildGlobalSearchCacheKey(12, 'flow test');
      const item: GlobalSearchCachedComicInfo = new GlobalSearchCachedComicInfo();
      item.id = 'comic-1';
      item.title = 'Flow Comic';
      item.url = 'https://example.test/comic-1';
      const items: GlobalSearchCachedComicInfo[] = [item];
      const data: GlobalSearchCacheData = createGlobalSearchCacheData('Flow Test', items, 'session-1');
      expect(keyA).assertEqual(keyB);
      expect(data.globalSearchSessionId).assertEqual('session-1');
      expect(data.results.length).assertEqual(1);
      expect(data.results[0].title).assertEqual('Flow Comic');
    });

    it('importFlowMonitorRecordsSnapshotBuckets', 0, () => {
      const monitor: ImportFlowMonitor = getImportFlowMonitor();
      const sessionId: string = monitor.createSessionId('unit_import');
      const info: ImportFlowSessionInfo = new ImportFlowSessionInfo();
      info.sessionId = sessionId;
      info.entrySource = ImportFlowEntrySource.DOWNLOAD_DIR;
      info.contentType = ImportFlowContentType.MANGA;
      info.displayName = 'unit.cbz';
      info.fileCount = 1;
      monitor.ensureSession(info);

      const slowEvent: ImportFlowEvent = monitor.createEvent(sessionId, ImportFlowEventType.ARCHIVE_PARSE_COMPLETED, 'unit_slow_parse');
      slowEvent.contentType = ImportFlowContentType.MANGA;
      slowEvent.elapsedMs = 3500;
      monitor.record(slowEvent);

      const failedEvent: ImportFlowEvent = monitor.createEvent(sessionId, ImportFlowEventType.ERROR, 'unit_failed');
      failedEvent.success = false;
      failedEvent.severity = ImportFlowSeverity.ERROR;
      failedEvent.errorMessage = 'unit failure';
      monitor.record(failedEvent);
      monitor.endSession(sessionId, 'unit_done');

      const snapshot: ImportFlowSnapshot = monitor.createSnapshot();
      const hasFailedEvent: boolean = snapshot.failedEvents.some((event: ImportFlowEvent): boolean => event.sessionId === sessionId);
      const hasSlowEvent: boolean = snapshot.slowEvents.some((event: ImportFlowEvent): boolean => event.sessionId === sessionId);
      const hasEndedSession: boolean = snapshot.recentSessions.some((summary: ImportFlowSummary): boolean => summary.sessionId === sessionId && summary.endReason === 'unit_done');
      expect(hasFailedEvent).assertTrue();
      expect(hasSlowEvent).assertTrue();
      expect(hasEndedSession).assertTrue();
      expect(snapshot.recentEventCount <= 260).assertTrue();
    });

    it('importArchiveParseCacheStoresSuccessfulParseOnly', 0, () => {
      const cache: ImportArchiveParseCache = getImportArchiveParseCache();
      cache.clear();
      const parsed: TestCompressionParsedStructure = new TestCompressionParsedStructure();
      cache.set('file://unit.cbz', parsed);
      const hit = cache.get('file://unit.cbz');
      const miss = cache.get('file://missing.cbz');
      expect(hit !== null).assertTrue();
      expect(hit ? hit.totalImageCount : 0).assertEqual(3);
      expect(miss === null).assertTrue();
      cache.clear();
    });

    it('importDuplicateDetectionCacheUsesSessionScopedKeys', 0, () => {
      const cache: ImportDuplicateDetectionCache = getImportDuplicateDetectionCache();
      cache.clear();
      const candidate: ExistingMangaCandidate = {
        id: 'manga-1',
        title: 'Unit Manga',
        author: 'Unit',
        coverUrl: '',
        chapterCount: 2
      };
      cache.set('session-a', 'Unit Manga', 'manga', 'single', [candidate]);
      const hit = cache.get('session-a', 'Unit Manga', 'manga', 'single');
      const miss = cache.get('session-b', 'Unit Manga', 'manga', 'single');
      expect(hit !== null).assertTrue();
      expect(hit ? hit.length : 0).assertEqual(1);
      expect(miss === null).assertTrue();
      cache.clearSession('session-a');
      expect(cache.get('session-a', 'Unit Manga', 'manga', 'single') === null).assertTrue();
    });

    it('downloadCacheFlowMonitorRecordsSnapshotBuckets', 0, () => {
      const monitor: DownloadCacheFlowMonitor = getDownloadCacheFlowMonitor();
      const sessionId: string = monitor.createSessionId('unit_download_cache');
      const info: DownloadCacheFlowSessionInfo = new DownloadCacheFlowSessionInfo();
      info.sessionId = sessionId;
      info.entrySource = DownloadCacheEntrySource.ONLINE_IMAGE_LOADER;
      info.contentType = DownloadCacheContentType.IMAGE;
      info.contentId = 'unit-content';
      info.chapterId = 'unit-chapter';
      info.sourceId = 1;
      info.sourceKey = 'source_1';
      info.totalCount = 1;
      monitor.ensureSession(info);

      const slowEvent: DownloadCacheFlowEvent = monitor.createEvent(
        sessionId,
        DownloadCacheFlowEventType.HTTP_COMPLETED,
        DownloadCacheFlowStage.NETWORK,
        'unit_slow_http'
      );
      slowEvent.elapsedMs = 6000;
      slowEvent.byteCount = 1024;
      monitor.record(slowEvent);

      const failedEvent: DownloadCacheFlowEvent = monitor.createEvent(
        sessionId,
        DownloadCacheFlowEventType.HTTP_FAILED,
        DownloadCacheFlowStage.NETWORK,
        'unit_failed_http'
      );
      failedEvent.success = false;
      failedEvent.severity = DownloadCacheFlowSeverity.ERROR;
      failedEvent.errorMessage = 'unit failure';
      monitor.record(failedEvent);
      monitor.endSession(sessionId, 'unit_done');

      const snapshot: DownloadCacheFlowSnapshot = monitor.createSnapshot();
      const hasFailedEvent: boolean = snapshot.failedEvents.some((event: DownloadCacheFlowEvent): boolean => event.sessionId === sessionId);
      const hasSlowEvent: boolean = snapshot.slowEvents.some((event: DownloadCacheFlowEvent): boolean => event.sessionId === sessionId);
      const hasEndedSession: boolean = snapshot.recentSessions.some((summary: DownloadCacheFlowSummary): boolean => summary.sessionId === sessionId && summary.endReason === 'unit_done');
      expect(hasFailedEvent).assertTrue();
      expect(hasSlowEvent).assertTrue();
      expect(hasEndedSession).assertTrue();
      expect(snapshot.recentEventCount <= 320).assertTrue();
    });

    it('downloadCacheFailureTtlCacheSkipsOnlyWhenAllowed', 0, () => {
      const cache: DownloadCacheFailureTtlCache = getDownloadCacheFailureTtlCache();
      cache.clear();
      cache.recordFailure(1, 'source_1', 'cache_a', 'network', 'unit failure', 60000);
      expect(cache.shouldSkip(1, 'source_1', 'cache_a', 'network', false)).assertFalse();
      expect(cache.shouldSkip(1, 'source_1', 'cache_a', 'network', true)).assertTrue();
      expect(cache.getErrorMessage(1, 'source_1', 'cache_a', 'network')).assertEqual('unit failure');
      cache.clear();
    });

    it('downloadCacheSourceLimiterQueuesAndReleases', 0, async () => {
      const limiter: DownloadCacheSourceLimiter = getDownloadCacheSourceLimiter();
      limiter.clear();
      const firstPermit: DownloadCacheLimiterPermit = await limiter.acquire('unit_source', 1);
      let secondResolved: boolean = false;
      const secondPromise: Promise<DownloadCacheLimiterPermit> = limiter.acquire('unit_source', 1).then((permit: DownloadCacheLimiterPermit): DownloadCacheLimiterPermit => {
        secondResolved = true;
        return permit;
      });
      expect(secondResolved).assertFalse();
      limiter.release(firstPermit);
      const secondPermit: DownloadCacheLimiterPermit = await secondPromise;
      expect(secondResolved).assertTrue();
      expect(secondPermit.waitedMs >= 0).assertTrue();
      limiter.release(secondPermit);
      limiter.clear();
    });

    it('cacheStatusIncrementalStoreClonesAndInvalidates', 0, () => {
      const store: CacheStatusIncrementalStore = getCacheStatusIncrementalStore();
      store.clear();
      const chapter: CacheStatusIncrementalChapter = new CacheStatusIncrementalChapter();
      chapter.chapterId = 'chapter-1';
      chapter.chapterTitle = 'Chapter 1';
      chapter.chapterIndex = 0;
      chapter.isCached = true;
      chapter.cachedPageCount = 3;
      chapter.totalPageCount = 3;
      chapter.cacheSize = 1024;
      const stats: CacheStatusIncrementalStats = new CacheStatusIncrementalStats();
      stats.contentId = 'manga-1';
      stats.contentType = 'manga';
      stats.title = 'Manga 1';
      stats.sourceId = 1;
      stats.cachedChapterCount = 1;
      stats.totalChapterCount = 1;
      stats.cachedPageCount = 3;
      stats.totalPageCount = 3;
      stats.cacheSize = 1024;
      stats.chapterStats = [chapter];
      store.set('manga', 1, 'manga-1', stats);

      const firstHit: CacheStatusIncrementalStats | null = store.get('manga', 1, 'manga-1');
      expect(firstHit !== null).assertTrue();
      if (firstHit !== null) {
        firstHit.chapterStats[0].cachedPageCount = 0;
      }
      const secondHit: CacheStatusIncrementalStats | null = store.get('manga', 1, 'manga-1');
      expect(secondHit !== null).assertTrue();
      expect(secondHit !== null ? secondHit.chapterStats[0].cachedPageCount : 0).assertEqual(3);
      store.invalidate('manga', 1, 'manga-1');
      expect(store.get('manga', 1, 'manga-1') === null).assertTrue();
      store.clear();
    });

    it('homeLoadFlowMonitorRecordsSnapshotBuckets', 0, () => {
      const monitor: HomeLoadFlowMonitor = getHomeLoadFlowMonitor();
      const sessionId: string = monitor.createSessionId('unit_home_load');
      const info: HomeLoadFlowSessionInfo = new HomeLoadFlowSessionInfo();
      info.sessionId = sessionId;
      info.entryReason = HomeLoadFlowEntryReason.NORMAL;
      info.primaryTab = HomeLoadFlowPrimaryTab.LIBRARY;
      info.routeTarget = '';
      info.widgetTarget = '';
      info.privacyMode = false;
      info.sfwMode = false;
      monitor.ensureSession(info);

      const slowEvent: HomeLoadFlowEvent = monitor.createEvent(
        sessionId,
        HomeLoadFlowEventType.FIRST_SCREEN_READY,
        HomeLoadFlowStage.FIRST_SCREEN,
        'unit_slow_first_screen'
      );
      slowEvent.elapsedMs = 3000;
      slowEvent.itemCount = 2;
      monitor.record(slowEvent);

      const failedEvent: HomeLoadFlowEvent = monitor.createEvent(
        sessionId,
        HomeLoadFlowEventType.ERROR,
        HomeLoadFlowStage.DEFERRED,
        'unit_failed'
      );
      failedEvent.success = false;
      failedEvent.severity = HomeLoadFlowSeverity.ERROR;
      failedEvent.errorMessage = 'unit failure';
      monitor.record(failedEvent);
      monitor.endSession(sessionId, 'unit_done');

      const snapshot: HomeLoadFlowSnapshot = monitor.createSnapshot();
      const hasFailedEvent: boolean = snapshot.failedEvents.some((event: HomeLoadFlowEvent): boolean => event.sessionId === sessionId);
      const hasSlowEvent: boolean = snapshot.slowEvents.some((event: HomeLoadFlowEvent): boolean => event.sessionId === sessionId);
      const hasEndedSession: boolean = snapshot.recentSessions.some((summary: HomeLoadFlowSummary): boolean => summary.sessionId === sessionId && summary.endReason === 'unit_done');
      expect(hasFailedEvent).assertTrue();
      expect(hasSlowEvent).assertTrue();
      expect(hasEndedSession).assertTrue();
      expect(snapshot.recentEventCount <= 260).assertTrue();
    });

    it('basicDataSourceStableUpdateSkipsChangesAndReloads', 0, () => {
      const dataSource: BasicDataSource<TestStableItem> = new BasicDataSource<TestStableItem>();
      const listener: TestDataChangeListener = new TestDataChangeListener();
      dataSource.registerDataChangeListener(listener);
      dataSource.setData([
        new TestStableItem('a', 'Alpha'),
        new TestStableItem('b', 'Beta')
      ]);
      expect(listener.reloadCount).assertEqual(1);

      const sameResult: BasicDataSourceStableUpdateResult = dataSource.setDataStable(
        [
          new TestStableItem('a', 'Alpha'),
          new TestStableItem('b', 'Beta')
        ],
        (item: TestStableItem, _index: number): string => item.id,
        (item: TestStableItem, _index: number): string => `${item.id}|${item.title}`
      );
      expect(sameResult.skipped).assertTrue();
      expect(listener.reloadCount).assertEqual(1);
      expect(listener.changeCount).assertEqual(0);

      const changedResult: BasicDataSourceStableUpdateResult = dataSource.setDataStable(
        [
          new TestStableItem('a', 'Alpha 2'),
          new TestStableItem('b', 'Beta')
        ],
        (item: TestStableItem, _index: number): string => item.id,
        (item: TestStableItem, _index: number): string => `${item.id}|${item.title}`
      );
      expect(changedResult.reloaded).assertFalse();
      expect(changedResult.changedCount).assertEqual(1);
      expect(listener.changeCount).assertEqual(1);

      const reorderedResult: BasicDataSourceStableUpdateResult = dataSource.setDataStable(
        [
          new TestStableItem('b', 'Beta'),
          new TestStableItem('a', 'Alpha 2')
        ],
        (item: TestStableItem, _index: number): string => item.id,
        (item: TestStableItem, _index: number): string => `${item.id}|${item.title}`
      );
      expect(reorderedResult.reloaded).assertTrue();
      expect(listener.reloadCount).assertEqual(2);
    });

    it('homeCoverFailureTtlCacheSkipsBackgroundOnlyWithinTtl', 0, () => {
      const cache: HomeCoverFailureTtlCache = getHomeCoverFailureTtlCache();
      cache.clear();
      cache.recordFailure('cover-a', 'unit failure', 1000);
      expect(cache.shouldSkipBackground('cover-a', false, 2000)).assertTrue();
      expect(cache.shouldSkipBackground('cover-a', true, 2000)).assertFalse();
      expect(cache.getMessage('cover-a')).assertEqual('unit failure');
      expect(cache.shouldSkipBackground('cover-a', false, 1000 + 6 * 60 * 1000)).assertFalse();
      cache.recordFailure('cover-b', 'unit failure', 1000);
      cache.clearKey('cover-b');
      expect(cache.shouldSkipBackground('cover-b', false, 2000)).assertFalse();
      cache.clear();
    });

    it('mangaImageFitPlannerPreservesAspectAndReportsOverflow', 0, () => {
      const planner: MangaImageFitPlanner = new MangaImageFitPlanner();
      const fitWidth: MangaImageFitLayout = planner.resolve('fit_width', 800, 1000, 400, 600, 2);
      expect(fitWidth.width).assertEqual(400);
      expect(fitWidth.height).assertEqual(500);
      expect(fitWidth.overflowX).assertFalse();
      expect(fitWidth.overflowY).assertFalse();

      const fitHeight: MangaImageFitLayout = planner.resolve('fit_height', 800, 1000, 400, 600, 2);
      expect(fitHeight.width).assertEqual(480);
      expect(fitHeight.height).assertEqual(600);
      expect(fitHeight.overflowX).assertTrue();
      expect(fitHeight.overflowY).assertFalse();

      const original: MangaImageFitLayout = planner.resolve('original', 800, 1000, 400, 600, 2);
      expect(original.width).assertEqual(400);
      expect(original.height).assertEqual(500);
      expect(original.usedFallback).assertFalse();

      const tallPage: MangaImageFitLayout = planner.resolve('fit_width', 600, 1200, 400, 600, 2);
      expect(tallPage.overflowY).assertTrue();
      expect(resolveMangaImageFitMode('unsupported')).assertEqual(MangaImageFitMode.FIT_WIDTH);
      expect(DEFAULT_READING_SETTINGS.fitMode).assertEqual(MangaImageFitMode.FIT_WIDTH);

      const unknownDimensions: MangaImageFitLayout = planner.resolve('fit_height', 0, 0, 400, 600, 2);
      expect(unknownDimensions.usedFallback).assertTrue();
      expect(unknownDimensions.width).assertEqual(400);
      expect(unknownDimensions.height).assertEqual(600);
    });

    it('coverPreloadBatchResultTracksPartialSuccess', 0, () => {
      const results: CoverPreloadResult[] = [
        new CoverPreloadResult('https://example.test/cover-a.jpg', true),
        new CoverPreloadResult('https://example.test/cover-b.jpg', false)
      ];
      expect(results.length).assertEqual(2);
      expect(results[0].succeeded).assertTrue();
      expect(results[1].succeeded).assertFalse();

      const failureCache: HomeCoverFailureTtlCache = getHomeCoverFailureTtlCache();
      failureCache.clear();
      failureCache.recordFailure('cover-a-manga-1', 'old failure', 1000);
      failureCache.recordFailure('cover-a-manga-2', 'old failure', 1000);
      const keysByUrl: Map<string, string[]> = new Map<string, string[]>();
      keysByUrl.set('https://example.test/cover-a.jpg', ['cover-a-manga-1', 'cover-a-manga-2']);
      keysByUrl.set('https://example.test/cover-b.jpg', ['cover-b-manga']);

      const processor: HomeCoverPreloadResultProcessor = new HomeCoverPreloadResultProcessor();
      const summary = processor.process(results, keysByUrl, failureCache, 2000);
      expect(summary.succeededCount).assertEqual(1);
      expect(summary.failedCount).assertEqual(1);
      expect(failureCache.shouldSkipBackground('cover-a-manga-1', false, 2001)).assertFalse();
      expect(failureCache.shouldSkipBackground('cover-a-manga-2', false, 2001)).assertFalse();
      expect(failureCache.shouldSkipBackground('cover-b-manga', false, 2001)).assertTrue();
      expect(failureCache.getMessage('cover-b-manga')).assertEqual('预加载未返回 PixelMap');
      failureCache.clear();
    });

    it('transferredPdfValidationAcceptsParsedPagesWithoutMetadataTitle', 0, () => {
      const metadata: EBookMetadata = {
        title: '',
        author: '',
        publisher: '',
        publishDate: '',
        isbn: '',
        language: '',
        description: '',
        coverImagePath: '',
        tags: [],
        rating: 0
      };
      const pageChapter: EBookChapter = {
        id: 'pdf_page_parser-book_0',
        bookId: 'parser-book',
        chapterNumber: 1,
        title: '第 1 页',
        content: '',
        startPosition: 0,
        endPosition: 1,
        wordCount: 0,
        createTime: 1
      };
      const validPdf: EBook = new EBook(
        'parser-book', EBookFormat.PDF, '/tmp/parser-book.pdf', 1024, metadata, [pageChapter]
      );
      const validator: TransferredBookValidation = new TransferredBookValidation();
      expect(validator.hasUsablePdfPages(validPdf)).assertTrue();
      expect(validator.getPdfFallbackTitle('C:\\Books\\source-report.pdf', 'target-id')).assertEqual('source-report');

      const fallbackChapter: EBookChapter = {
        id: 'pdf_chapter_1',
        bookId: 'empty-pdf',
        chapterNumber: 1,
        title: '全文',
        content: '',
        startPosition: 0,
        endPosition: 0,
        wordCount: 0,
        createTime: 1
      };
      const invalidPdf: EBook = new EBook(
        'empty-pdf', EBookFormat.PDF, '/tmp/empty-pdf.pdf', 1024, metadata, [fallbackChapter]
      );
      expect(validator.hasUsablePdfPages(invalidPdf)).assertFalse();
      expect(validator.getPdfFallbackTitle('', 'target-id')).assertEqual('PDF文档');
    });

    it('mangaImageRetryCoordinatorTransitionsToForceRefresh', 0, () => {
      const coordinator: MangaImageRetryCoordinator = new MangaImageRetryCoordinator();
      const key: string = buildMangaImageRetryKey('chapter-1', 'page-1');

      const automatic: MangaImageRetryDecision = coordinator.recordFailure(key, 'initial failed');
      expect(automatic.shouldRetry).assertTrue();
      expect(automatic.automatic).assertTrue();
      expect(automatic.retryMode).assertEqual(MangaAssetRetryMode.CACHE_FIRST);
      expect(coordinator.isLoading(key)).assertTrue();

      const terminalAfterAutomatic: MangaImageRetryDecision = coordinator.recordFailure(key, 'automatic failed');
      expect(terminalAfterAutomatic.shouldRetry).assertFalse();
      expect(terminalAfterAutomatic.showTerminalError).assertTrue();
      expect(coordinator.getPhase(key)).assertEqual(MangaImageRetryPhase.TERMINAL);

      const firstManual: MangaImageRetryDecision = coordinator.beginManualRetry(key);
      expect(firstManual.retryMode).assertEqual(MangaAssetRetryMode.CACHE_FIRST);
      expect(firstManual.attempt).assertEqual(1);
      coordinator.recordFailure(key, 'manual cache failed');

      const secondManual: MangaImageRetryDecision = coordinator.beginManualRetry(key);
      expect(secondManual.retryMode).assertEqual(MangaAssetRetryMode.FORCE_REFRESH);
      expect(secondManual.attempt).assertEqual(2);
    });

    it('mangaImageRetryCoordinatorResetsAndIsolatesPages', 0, () => {
      const coordinator: MangaImageRetryCoordinator = new MangaImageRetryCoordinator();
      const firstKey: string = buildMangaImageRetryKey('chapter-1', 'page-1');
      const secondKey: string = buildMangaImageRetryKey('chapter-1', 'page-2');

      coordinator.recordFailure(firstKey, 'first failed');
      expect(coordinator.getPhase(secondKey)).assertEqual(MangaImageRetryPhase.IDLE);
      const firstManual: MangaImageRetryDecision = coordinator.beginManualRetry(firstKey);
      expect(firstManual.shouldRetry).assertFalse();

      coordinator.markSuccess(firstKey);
      expect(coordinator.getPhase(firstKey)).assertEqual(MangaImageRetryPhase.IDLE);
      const automaticAfterSuccess: MangaImageRetryDecision = coordinator.recordFailure(firstKey, 'failed again');
      expect(automaticAfterSuccess.automatic).assertTrue();
      expect(automaticAfterSuccess.attempt).assertEqual(1);
    });

    it('mangaAssetRequestFactoryCarriesRetryContract', 0, () => {
      const factory: MangaAssetRequestFactory = new MangaAssetRequestFactory();
      const page: MangaPage = createMangaAssetTestPage();
      const context: MangaAssetRequestContext = new MangaAssetRequestContext();
      context.chapterId = 'chapter-1';
      context.chapterPageIndex = 0;
      context.imageUrl = page.imageUrl;
      context.contentType = 'OnlineDownloaded';
      context.reason = MangaAssetLoadReason.RETRY;
      context.retryMode = MangaAssetRetryMode.FORCE_REFRESH;
      context.priority = 10;
      context.sourceTypeOverride = ImageSourceType.NETWORK;
      context.useLegadoV2ImageTransport = true;

      const request: MangaAssetLoadRequest = factory.build(page, 7, context);
      expect(request.retryMode).assertEqual(MangaAssetRetryMode.FORCE_REFRESH);
      expect(request.reason).assertEqual(MangaAssetLoadReason.RETRY);
      expect(request.priority).assertEqual(10);
      expect(request.sourceType).assertEqual(ImageSourceType.NETWORK);
      expect(request.imageUrl).assertEqual(page.imageUrl);
      expect(request.loadOptions.forceRefresh === true).assertTrue();
      expect(request.loadOptions.skipFailureTtl === true).assertTrue();
      expect(request.loadOptions.pageIndex).assertEqual(0);
      expect(request.useLegadoV2ImageTransport).assertTrue();

      const forceKey: string = buildMangaAssetRequestKey(request);
      const cacheFirstContext: MangaAssetRequestContext = new MangaAssetRequestContext();
      cacheFirstContext.chapterId = context.chapterId;
      cacheFirstContext.chapterPageIndex = context.chapterPageIndex;
      cacheFirstContext.imageUrl = context.imageUrl;
      cacheFirstContext.contentType = context.contentType;
      cacheFirstContext.reason = MangaAssetLoadReason.RETRY;
      cacheFirstContext.retryMode = MangaAssetRetryMode.CACHE_FIRST;
      cacheFirstContext.priority = 10;
      cacheFirstContext.sourceTypeOverride = ImageSourceType.NETWORK;
      const cacheFirstRequest: MangaAssetLoadRequest = factory.build(page, 7, cacheFirstContext);
      const cacheFirstKey: string = buildMangaAssetRequestKey(cacheFirstRequest);
      expect(forceKey === cacheFirstKey).assertFalse();
      expect(cacheFirstRequest.loadOptions.forceRefresh === true).assertFalse();
      expect(cacheFirstRequest.loadOptions.skipFailureTtl === true).assertFalse();
    });

    it('mangaPageLoadResolverUsesWebtoonGlobalIndex', 0, () => {
      const resolver: MangaPageLoadResolver = new MangaPageLoadResolver();
      const page: MangaPage = createMangaAssetTestPage();
      const chapter: MangaChapter = {} as MangaChapter;
      chapter.id = 'chapter-1';
      chapter.pages = [page];

      const normalContext: MangaPageResolveContext = new MangaPageResolveContext();
      normalContext.chapter = chapter;
      expect(resolver.resolveManagedPageIndex(page, -1, normalContext)).assertEqual(0);

      const webtoonContext: MangaPageResolveContext = new MangaPageResolveContext();
      webtoonContext.chapter = chapter;
      webtoonContext.isWebtoonMode = true;
      const pageRef: WebtoonPageRef = {
        page: page,
        chapterId: chapter.id,
        chapterPageIndex: 0,
        itemIndex: 12,
        orderIndex: 10
      };
      webtoonContext.webtoonPageRefById.set(page.id, pageRef);
      expect(resolver.resolveManagedPageIndex(page, -1, webtoonContext)).assertEqual(12);
    });
  });

  describe('Continuation reading policy and transfer manifest', () => {
    it('defaultsToReadOnlyAndFallsBackToEnabledMode', 0, () => {
      const defaults: ContinuationReadingSettings = {
        readOnlyEnabled: true,
        importToLibraryEnabled: true,
        defaultMode: ContinuationTransferMode.READ_ONLY
      };
      expect(resolveContinuationTransferMode(defaults)).assertEqual(ContinuationTransferMode.READ_ONLY);

      const importOnly: ContinuationReadingSettings = {
        readOnlyEnabled: false,
        importToLibraryEnabled: true,
        defaultMode: ContinuationTransferMode.READ_ONLY
      };
      expect(resolveContinuationTransferMode(importOnly)).assertEqual(ContinuationTransferMode.IMPORT_TO_LIBRARY);
      expect(normalizeContinuationReadingSettings(importOnly).defaultMode).assertEqual(ContinuationTransferMode.IMPORT_TO_LIBRARY);

      const disabled: ContinuationReadingSettings = {
        readOnlyEnabled: false,
        importToLibraryEnabled: false,
        defaultMode: ContinuationTransferMode.READ_ONLY
      };
      expect(resolveContinuationTransferMode(disabled)).assertEqual(ContinuationTransferMode.DISABLED);
    });

    it('acceptsOnlyMatchingVersionedPackageIdentityAndSafePaths', 0, () => {
      const request: ContinuationTransferRequest = {
        schemaVersion: 1,
        sessionId: 'session-1',
        mode: ContinuationTransferMode.READ_ONLY,
        contentType: 'manga',
        sourceBookId: 'comic-1',
        isLocal: false,
        chapterIndex: 3,
        pageIndex: 2,
        offset: 0
      };
      const file: ContinuationTransferFile = {
        name: 'page.bin',
        relativePath: 'pages/chapter-3/page.bin',
        sourcePath: '',
        size: 32,
        sha256: 'a'.repeat(64)
      };
      const comic: RemoteComicMetadata = {
        id: 'comic-1',
        title: 'Test comic',
        author: 'Test author',
        description: '',
        coverUrl: '',
        coverLocalPath: '',
        sourceId: '1',
        externalId: 'external-1',
        status: 'ongoing',
        tags: [],
        rating: 0,
        chapterCount: 1,
        lastUpdateTime: 1,
        addTime: 1,
        contentType: 'manga',
        isNSFW: 0,
        isPrivate: 0
      };
      const bundle: MangaTransferBundle = {
        comic: comic,
        chapters: [],
        chapterPages: [],
        files: []
      };
      const manifest: ContinuationTransferManifest = {
        schemaVersion: 1,
        sessionId: 'session-1',
        mode: ContinuationTransferMode.READ_ONLY,
        contentType: 'manga',
        sourceBookId: 'comic-1',
        isLocal: false,
        title: 'Test comic',
        author: 'Test author',
        coverPath: '',
        sourceId: '1',
        sourceName: 'Test source',
        bookUrl: '',
        chapterIndex: 3,
        pageIndex: 2,
        offset: 0,
        chapterTitle: 'Chapter 4',
        chapterCount: 4,
        isCompleteBook: false,
        ebook: null,
        manga: bundle,
        novelBook: null,
        novelChapters: [],
        chapterContents: [],
        files: [file]
      };

      expect(isContinuationManifestCompatible(manifest, request)).assertTrue();
      expect(normalizeContinuationPackagePath('pages\\chapter-3\\page.bin')).assertEqual('pages/chapter-3/page.bin');

      bundle.comic.coverLocalPath = '../outside.jpg';
      expect(isContinuationManifestCompatible(manifest, request)).assertFalse();
      bundle.comic.coverLocalPath = '';

      let rejectedTraversal = false;
      try {
        normalizeContinuationPackagePath('../outside.bin');
      } catch (_error) {
        rejectedTraversal = true;
      }
      expect(rejectedTraversal).assertTrue();

      manifest.schemaVersion = 2;
      expect(isContinuationManifestCompatible(manifest, request)).assertFalse();
    });
  });
}

class TestCompressionParsedStructure implements CompressionParsedStructure {
  public hasComicInfo: boolean = false;
  public isMultiLayer: boolean = false;
  public detectedChapters: DetectedChapterInfo[] = [];
  public rootImageCount: number = 1;
  public totalImageCount: number = 3;
  public extractedPath: string = '/tmp/unit';
  public tempDirectories: string[] = [];
  public warnings: string[] = [];
}
