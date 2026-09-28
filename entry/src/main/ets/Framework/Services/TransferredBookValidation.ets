import { EBook, EBookFormat } from 'manxia_core/src/main/ets/Models/EBookModels';

export class TransferredBookValidation {
  public hasUsablePdfPages(ebook: EBook): boolean {
    if (ebook.format !== EBookFormat.PDF || ebook.fileSize <= 0) {
      return false;
    }
    const pageIdPrefix: string = `pdf_page_${ebook.id}_`;
    for (const chapter of ebook.chapters) {
      if (chapter.id.startsWith(pageIdPrefix) && chapter.endPosition > chapter.startPosition) {
        return true;
      }
    }
    return false;
  }

  public getPdfFallbackTitle(originalFileName: string, targetBookId: string): string {
    const normalizedPath: string = originalFileName.trim().replace(/\\/g, '/');
    const separatorIndex: number = normalizedPath.lastIndexOf('/');
    let title: string = separatorIndex >= 0
      ? normalizedPath.substring(separatorIndex + 1)
      : normalizedPath;
    if (title.toLowerCase().endsWith('.pdf')) {
      title = title.substring(0, title.length - 4);
    }
    title = title.trim();
    if (title.length <= 0 || title === targetBookId) {
      return 'PDF文档';
    }
    return title;
  }
}
