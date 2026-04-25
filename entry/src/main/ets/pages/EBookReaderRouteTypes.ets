export interface EBookReaderParams {
  bookId: string;
  coverComponentId?: string;
  routerBackOnClose?: boolean;
  forceReaderKit?: boolean;
  autoStartReadAloud?: boolean;
  autoOpenReadAloudPlayer?: boolean;
}
