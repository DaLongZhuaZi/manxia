import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { NovelSearchResult } from 'manxia_core/src/main/ets/Models/NovelModels';
import { UnifiedContentType, UnifiedDetailPageParams } from 'manxia_core/src/main/ets/Models/UnifiedContentModels';
import { MangaDetailPageParams } from '../../pages/MangaDetailPage';
import { NovelDetailPageParams } from '../../pages/NovelBookshelfPage';
import { DetailPageType, PageSettingsHelper } from '../../pages/settings/PageSettingsSubPage';
import { getLegadoMangaSourceBridge, LegadoMangaVirtualSource } from './LegadoMangaSourceBridge';
import {
  LegadoExploreDetailBridgeStatus,
  LegadoExploreDetailRouteDecision,
  LegadoExploreDetailRouteKind,
  LegadoExploreDetailRouteReason,
  LegadoExploreDetailRouteResolver
} from 'manxia_novel/src/main/ets/Framework/Novel/LegadoExploreDetailRouteResolver';
import { LegadoBookSource } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoSourceTypes';
import { getNovelSourceManager } from './NovelSourceManager';

const TAG: string = 'LegadoExploreDetailNavigator';

export enum LegadoExploreDetailOpenStatus {
  OPENED = 'opened',
  REJECTED = 'rejected'
}

export class LegadoExploreDetailOpenResult {
  readonly status: LegadoExploreDetailOpenStatus;
  readonly diagnostic: string;
  readonly userMessage: string;

  constructor(status: LegadoExploreDetailOpenStatus, diagnostic: string, userMessage: string = '') {
    this.status = status;
    this.diagnostic = diagnostic;
    this.userMessage = userMessage;
  }
}

function recordSafeRouteDiagnostic(
  decision: LegadoExploreDetailRouteDecision,
  bridgeStatus: LegadoExploreDetailBridgeStatus
): string {
  const diagnostic = decision.toSafeDiagnostic(bridgeStatus);
  AppStorage.setOrCreate<string>('legadoExploreDetailRouteDiagnostic', diagnostic);
  logger.warn(TAG, `EXPLORE_DETAIL_ROUTE ${diagnostic}`);
  return diagnostic;
}

function getRejectedRouteMessage(reason: LegadoExploreDetailRouteReason): string {
  if (reason === LegadoExploreDetailRouteReason.UNSUPPORTED_SOURCE_TYPE) {
    return '该书源类型暂不支持打开详情';
  }
  if (reason === LegadoExploreDetailRouteReason.SOURCE_IDENTITY_MISMATCH ||
    reason === LegadoExploreDetailRouteReason.RESOLVED_SOURCE_IDENTITY_MISMATCH) {
    return '书源结果与当前书源不一致，请刷新后重试';
  }
  return '书源运行时信息尚未就绪，请刷新后重试';
}

function openMangaDetail(
  pathStack: NavPathStack,
  book: NovelSearchResult,
  virtualSource: LegadoMangaVirtualSource
): void {
  const pageType = PageSettingsHelper.getMangaDetailPageType();
  if (pageType === DetailPageType.UNIFIED) {
    const unifiedParams: UnifiedDetailPageParams = {
      contentType: UnifiedContentType.MANGA,
      contentId: book.bookUrl,
      sourceId: String(virtualSource.sourceId),
      sourceName: book.sourceName,
      sourcePkg: virtualSource.pkg,
      cachedTitle: book.name,
      cachedCover: book.coverUrl,
      cachedAuthor: book.author
    };
    pathStack.pushPathByName('UnifiedDetailPage', unifiedParams);
    return;
  }
  const params: MangaDetailPageParams = {
    mangaId: book.bookUrl,
    sourceId: virtualSource.sourceId,
    sourcePkg: virtualSource.pkg,
    cachedTitle: book.name,
    cachedCover: book.coverUrl
  };
  pathStack.pushPathByName('MangaDetailPage', params);
}

function openNovelDetail(pathStack: NavPathStack, book: NovelSearchResult): void {
  const pageType = PageSettingsHelper.getNovelDetailPageType();
  if (pageType === DetailPageType.UNIFIED) {
    const unifiedParams: UnifiedDetailPageParams = {
      contentType: UnifiedContentType.NOVEL,
      contentId: book.bookUrl,
      sourceId: book.sourceId,
      sourceName: book.sourceName,
      cachedTitle: book.name,
      cachedCover: book.coverUrl,
      cachedAuthor: book.author,
      forceNovelNetworkRefresh: true,
      novelRequestCarrierKey: book.requestCarrierKey,
      novelBookVariable: book.variable
    };
    pathStack.pushPathByName('UnifiedDetailPage', unifiedParams);
    return;
  }
  const params: NovelDetailPageParams = {
    sourceId: book.sourceId,
    bookUrl: book.bookUrl,
    bookName: book.name,
    author: book.author,
    kind: book.kind,
    intro: book.intro,
    coverUrl: book.coverUrl,
    latestChapterTitle: book.latestChapterTitle,
    wordCount: book.wordCount,
    sourceName: book.sourceName,
    requestCarrierKey: book.requestCarrierKey,
    bookVariable: book.variable
  };
  pathStack.pushPathByName('NovelDetailPage', params);
}

/** Owns the shared IMAGE-vs-NOVEL Explore detail route for every UI entry. */
export async function openLegadoExploreDetail(
  pathStack: NavPathStack,
  selectedSourceId: string,
  book: NovelSearchResult
): Promise<LegadoExploreDetailOpenResult> {
  const source: LegadoBookSource | null = getNovelSourceManager().getSource(book.sourceId);
  const resolver = new LegadoExploreDetailRouteResolver();
  const decision = resolver.resolve(book.sourceId, selectedSourceId, source);
  if (decision.route === LegadoExploreDetailRouteKind.REJECTED || source === null) {
    const diagnostic = recordSafeRouteDiagnostic(decision, LegadoExploreDetailBridgeStatus.NOT_APPLICABLE);
    return new LegadoExploreDetailOpenResult(
      LegadoExploreDetailOpenStatus.REJECTED,
      diagnostic,
      getRejectedRouteMessage(decision.reason)
    );
  }

  if (decision.route === LegadoExploreDetailRouteKind.MANGA) {
    let virtualSource: LegadoMangaVirtualSource | null = null;
    try {
      virtualSource = await getLegadoMangaSourceBridge().ensureVirtualComicSource(source);
    } catch (error) {
      logger.warn(TAG, 'EXPLORE_DETAIL_ROUTE bridge setup rejected');
    }
    if (virtualSource === null || virtualSource.sourceId <= 0) {
      const diagnostic = recordSafeRouteDiagnostic(decision, LegadoExploreDetailBridgeStatus.UNAVAILABLE);
      return new LegadoExploreDetailOpenResult(
        LegadoExploreDetailOpenStatus.REJECTED,
        diagnostic,
        '漫画书源桥接失败，请稍后重试'
      );
    }
    const diagnostic = recordSafeRouteDiagnostic(decision, LegadoExploreDetailBridgeStatus.READY);
    openMangaDetail(pathStack, book, virtualSource);
    return new LegadoExploreDetailOpenResult(LegadoExploreDetailOpenStatus.OPENED, diagnostic);
  }

  const diagnostic = recordSafeRouteDiagnostic(decision, LegadoExploreDetailBridgeStatus.NOT_APPLICABLE);
  openNovelDetail(pathStack, book);
  return new LegadoExploreDetailOpenResult(LegadoExploreDetailOpenStatus.OPENED, diagnostic);
}
