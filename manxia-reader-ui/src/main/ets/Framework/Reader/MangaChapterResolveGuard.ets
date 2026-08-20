export enum MangaChapterResolveGuardStatus {
  OK = 'ok',
  MISSING_MANGA_EXTERNAL_ID = 'missing_manga_external_id',
  MISSING_CHAPTER_EXTERNAL_ID = 'missing_chapter_external_id',
  EMPTY_ENGINE_PAGES = 'empty_engine_pages',
  EMPTY_CACHE_PAGES = 'empty_cache_pages',
  ARCHIVE_FALLBACK = 'archive_fallback'
}

export class MangaChapterResolveGuardInput {
  public mangaExternalId: string = '';
  public chapterExternalId: string = '';
  public allowCacheFallback: boolean = false;
  public cachedPageCount: number = 0;
  public enginePageCount: number = 0;
  public archivePath: string = '';
  public archiveExists: boolean = false;
}

export class MangaChapterResolveGuardPlan {
  public status: MangaChapterResolveGuardStatus = MangaChapterResolveGuardStatus.OK;
  public shouldContinue: boolean = true;
  public shouldUseCacheFallback: boolean = false;
  public reason: string = 'chapter_resolve_ok';
  public detail: string = '';
}

export class MangaChapterResolveGuard {
  public buildPlan(input: MangaChapterResolveGuardInput): MangaChapterResolveGuardPlan {
    const plan: MangaChapterResolveGuardPlan = new MangaChapterResolveGuardPlan();
    if (input.mangaExternalId.length <= 0) {
      plan.status = MangaChapterResolveGuardStatus.MISSING_MANGA_EXTERNAL_ID;
      plan.shouldContinue = false;
      plan.reason = 'missing_manga_external_id';
    } else if (input.chapterExternalId.length <= 0) {
      plan.status = MangaChapterResolveGuardStatus.MISSING_CHAPTER_EXTERNAL_ID;
      plan.shouldContinue = false;
      plan.reason = 'missing_chapter_external_id';
    } else if (input.enginePageCount <= 0 && input.allowCacheFallback && input.cachedPageCount > 0) {
      plan.status = MangaChapterResolveGuardStatus.EMPTY_ENGINE_PAGES;
      plan.shouldUseCacheFallback = true;
      plan.reason = 'engine_empty_use_cache_fallback';
    } else if (input.enginePageCount <= 0 && input.cachedPageCount <= 0) {
      plan.status = MangaChapterResolveGuardStatus.EMPTY_ENGINE_PAGES;
      plan.shouldContinue = false;
      plan.reason = 'engine_and_cache_empty';
    } else if (input.archivePath.length > 0 && !input.archiveExists) {
      plan.status = MangaChapterResolveGuardStatus.ARCHIVE_FALLBACK;
      plan.shouldUseCacheFallback = true;
      plan.reason = 'archive_missing_use_legacy_fallback';
    }
    plan.detail = `mangaExternal=${input.mangaExternalId.length > 0}, chapterExternal=${input.chapterExternalId.length > 0}, enginePages=${input.enginePageCount}, cachedPages=${input.cachedPageCount}, archive=${input.archivePath}`;
    return plan;
  }
}
