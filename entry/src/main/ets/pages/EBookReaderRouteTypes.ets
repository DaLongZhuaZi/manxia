export interface EBookReaderParams {
  bookId: string;
  coverComponentId?: string;
  routerBackOnClose?: boolean;
  forceReaderKit?: boolean;
  autoStartReadAloud?: boolean;
  autoOpenReadAloudPlayer?: boolean;
  readerHostMode?: string;
  readerInstanceId?: string;
  readerTitle?: string;
  originImportId?: string;
  originImportKind?: string;
  readerOpenFlowId?: string;
}
