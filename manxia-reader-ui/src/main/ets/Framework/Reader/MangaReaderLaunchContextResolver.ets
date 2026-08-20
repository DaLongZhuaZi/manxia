import {
  MangaReadFlowSourceKind
} from './MangaReadFlowTypes';

export class MangaReaderLaunchContextInput {
  public contentType: string = '';
  public mangaId: string = '';
  public mangaTitle: string = '';
  public readerTitle: string = '';
  public chapterId: string = '';
  public pageIndex: number = 0;
  public sourceId: number = -1;
  public readerHostMode: string = '';
  public readerInstanceId: string = '';
  public originImportId: string = '';
  public originImportKind: string = '';
}

export class MangaReaderLaunchContext {
  public contentType: string = '';
  public sourceKind: MangaReadFlowSourceKind = MangaReadFlowSourceKind.LOCAL;
  public contentId: string = '';
  public contentTitle: string = '';
  public chapterId: string = '';
  public pageIndex: number = 0;
  public sourceId: number = -1;
  public readerHostMode: string = '';
  public readerInstanceId: string = '';
  public originImportId: string = '';
  public originImportKind: string = '';
  public isIsolatedInstance: boolean = false;
  public initKey: string = '';
}

export class MangaReaderLaunchContextResolver {
  public resolve(input: MangaReaderLaunchContextInput): MangaReaderLaunchContext {
    const context: MangaReaderLaunchContext = new MangaReaderLaunchContext();
    context.contentType = input.contentType;
    context.sourceKind = this.mapSourceKind(input.contentType);
    context.contentId = input.mangaId;
    context.contentTitle = input.readerTitle.length > 0 ? input.readerTitle : input.mangaTitle;
    context.chapterId = input.chapterId;
    context.pageIndex = input.pageIndex;
    context.sourceId = input.sourceId;
    context.readerHostMode = input.readerHostMode;
    context.readerInstanceId = input.readerInstanceId;
    context.originImportId = input.originImportId;
    context.originImportKind = input.originImportKind;
    context.isIsolatedInstance = input.readerHostMode.length > 0 || input.readerInstanceId.length > 0;
    context.initKey = `${context.contentId}|${context.chapterId}|${context.pageIndex}|${context.contentType}|${context.sourceId}|${context.originImportId}`;
    return context;
  }

  public mapSourceKind(contentType: string): MangaReadFlowSourceKind {
    if (contentType === 'OnlineUndownloaded') {
      return MangaReadFlowSourceKind.ONLINE_UNDOWNLOADED;
    }
    if (contentType === 'OnlineDownloaded') {
      return MangaReadFlowSourceKind.ONLINE_DOWNLOADED;
    }
    if (contentType === 'Suwayomi') {
      return MangaReadFlowSourceKind.SUWAYOMI;
    }
    if (contentType === 'Komga') {
      return MangaReadFlowSourceKind.KOMGA;
    }
    return MangaReadFlowSourceKind.LOCAL;
  }
}
