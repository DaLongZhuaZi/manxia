import { common } from '@kit.AbilityKit';
import { pdfService, pdfViewManager, PdfView } from '@kit.PDFKit';
import { image } from '@kit.ImageKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import { PdfTextIndexService } from '../Framework/Services/PdfTextIndexService';
import { EBookParserFactory, EBookCoverExtractor } from '../Framework/Parsers/EBookParser';
import { EBookDataManager } from 'manxia_core/src/main/ets/Framework/Data/EBookDataManager';
import fs from '@ohos.file.fs';

const TAG: string = 'PdfKitCapabilityProbe';

export class PdfProbeLine {
  name: string;
  pass: boolean;
  detail: string;
  elapsedMs: number;

  constructor(name: string, pass: boolean, detail: string, elapsedMs: number) {
    this.name = name;
    this.pass = pass;
    this.detail = detail;
    this.elapsedMs = elapsedMs;
  }
}

@Component
export struct PdfKitCapabilityProbePage {
  private probeScroller: Scroller = new Scroller();
  private probePathStack: NavPathStack | null = null;
  @State probeResults: PdfProbeLine[] = [];
  @State probeRunning: boolean = false;
  @State probeFinished: boolean = false;
  @State probeViewerPath: string = '';
  private probeController: pdfViewManager.PdfController = new pdfViewManager.PdfController();
  private probeViewLoaded: boolean = false;
  private probeViewEvents: number = 0;

  aboutToAppear(): void {
    logger.info(TAG, 'PROBE_START');
    this.registerViewListeners();
    void this.runProbe();
  }

  aboutToDisappear(): void {
    try {
      if (this.probeViewLoaded) {
        this.probeController.releaseDocument();
        this.probeViewLoaded = false;
      }
    } catch (error) {
      logger.warn(TAG, 'releaseDocument failed: ' + String(error));
    }
  }

  private registerViewListeners(): void {
    try {
      this.probeController.registerPageCountChangedListener((pageCount: number) => {
        this.probeViewEvents = this.probeViewEvents + 1;
        logger.info(TAG, 'view_event page_count=' + pageCount);
      });
      this.probeController.registerPageChangedListener((pageIndex: number) => {
        this.probeViewEvents = this.probeViewEvents + 1;
        logger.info(TAG, 'view_event page_changed=' + pageIndex);
      });
      this.probeController.registerScrollListener((param: pdfViewManager.ScrollParam) => {
        this.probeViewEvents = this.probeViewEvents + 1;
        logger.info(TAG, 'view_event scroll');
      });
      this.probeController.registerActionClickListener((info: pdfViewManager.RedirectInfo) => {
        this.probeViewEvents = this.probeViewEvents + 1;
        logger.info(TAG, 'view_event link_action type=' + info.actionType + ' content=' + info.content);
      });
      this.probeController.registerTextSelectedListener((param: pdfViewManager.TextSelectedParam) => {
        this.probeViewEvents = this.probeViewEvents + 1;
        logger.info(TAG, 'view_event text_selected');
      });
      logger.info(TAG, 'view listeners registered');
    } catch (error) {
      logger.warn(TAG, 'register listeners failed: ' + String(error));
    }
  }

  private addLine(name: string, pass: boolean, detail: string, elapsedMs: number): void {
    this.probeResults = this.probeResults.concat([new PdfProbeLine(name, pass, detail, elapsedMs)]);
    logger.info(TAG, (pass ? 'PASS ' : 'FAIL ') + name + ' | ' + detail + ' | ' + elapsedMs + 'ms');
  }

  private async runProbe(): Promise<void> {
    this.probeRunning = true;
    this.probeResults = [];
    try {
      const textPath: string = await this.prepareRawFiles();
      if (textPath.length > 0) {
        const dir: string = textPath.substring(0, textPath.lastIndexOf('/'));
        const encPath: string = dir + '/probe_encrypted.pdf';
        const imgPath: string = dir + '/probe_image_only.pdf';
        await this.testDocument(textPath, encPath, imgPath);
      }
    } catch (error) {
      this.addLine('probe', false, String(error), 0);
    }
    this.probeRunning = false;
    this.probeFinished = true;
    logger.info(TAG, 'PROBE_DONE total=' + this.probeResults.length + ' viewEvents=' + this.probeViewEvents);
  }

  private async prepareRawFiles(): Promise<string> {
    const startedAt: number = Date.now();
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const dir: string = ctx.filesDir + '/pdf_probe';
      try {
        SafeFileUtils.mkdirSync(dir, true);
      } catch (_mkdirError) {
      }
      const names: string[] = ['probe_text_outline.pdf', 'probe_encrypted.pdf', 'probe_image_only.pdf'];
      for (let i = 0; i < names.length; i++) {
        const name: string = names[i];
        const bytes: Uint8Array = await ctx.resourceManager.getRawFileContent('pdf_probe/' + name);
        const buffer: ArrayBuffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
        const target: string = dir + '/' + name;
        try {
          SafeFileUtils.unlinkSync(target);
        } catch (_unlinkError) {
        }
        const file = fs.openSync(target, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
        fs.writeSync(file.fd, buffer);
        fs.closeSync(file);
      }
      this.addLine('prepare_files', true, 'rawfiles=' + names.length, Date.now() - startedAt);
      return dir + '/probe_text_outline.pdf';
    } catch (error) {
      this.addLine('prepare_files', false, String(error), Date.now() - startedAt);
      return '';
    }
  }

  private countBookmarks(node: pdfService.Bookmark): number {
    let total: number = 1;
    try {
      const children: Array<pdfService.Bookmark> = node.getChildren();
      for (let i = 0; i < children.length; i++) {
        total = total + this.countBookmarks(children[i]);
      }
    } catch (_error) {
    }
    return total;
  }

  private async testDocument(textPath: string, encPath: string, imgPath: string): Promise<void> {
    const t0: number = Date.now();
    const doc: pdfService.PdfDocument = new pdfService.PdfDocument();
    try {
      const loadResult: pdfService.ParseResult = doc.loadDocument(textPath);
      this.addLine('load_text', loadResult === pdfService.ParseResult.PARSE_SUCCESS, 'ParseResult=' + String(loadResult), Date.now() - t0);
      if (loadResult !== pdfService.ParseResult.PARSE_SUCCESS) {
        return;
      }
    } catch (error) {
      this.addLine('load_text', false, String(error), Date.now() - t0);
      return;
    }

    const t1: number = Date.now();
    try {
      const count: number = doc.getPageCount();
      this.addLine('page_count', count > 0, 'pages=' + count, Date.now() - t1);
    } catch (error) {
      this.addLine('page_count', false, String(error), Date.now() - t1);
    }

    const t2: number = Date.now();
    try {
      const meta: pdfService.Metadata = doc.getMetadata();
      this.addLine('metadata', true, 'title=' + meta.title + '; author=' + meta.author + '; subject=' + meta.subject + '; keywords=' + meta.keywords + '; producer=' + meta.producer, Date.now() - t2);
    } catch (error) {
      this.addLine('metadata', false, String(error), Date.now() - t2);
    }

    const t3: number = Date.now();
    try {
      const roots: Array<pdfService.Bookmark> = doc.getRootBookmarks();
      let total: number = 0;
      let detail: string = '';
      for (let i = 0; i < roots.length; i++) {
        total = total + this.countBookmarks(roots[i]);
        if (i < 6) {
          const info: pdfService.BookmarkInfo = roots[i].getBookmarkInfo();
          const dest: pdfService.DestInfo = roots[i].getDestInfo();
          detail = detail + '[' + info.title + '->p' + dest.pageIndex + ']';
        }
      }
      this.addLine('outline', total > 0, 'roots=' + roots.length + '; total=' + total + '; ' + detail, Date.now() - t3);
    } catch (error) {
      this.addLine('outline', false, String(error), Date.now() - t3);
    }

    const t4: number = Date.now();
    try {
      const page0: pdfService.PdfPage = doc.getPage(0);
      const text: string = page0.getTextContent();
      this.addLine('text_extract', text.length > 0, 'len=' + text.length + '; head=' + text.substring(0, 48), Date.now() - t4);
    } catch (error) {
      this.addLine('text_extract', false, String(error), Date.now() - t4);
    }

    const t5: number = Date.now();
    try {
      let hits: number = 0;
      let first: string = '';
      await doc.searchKey('alpha', (results: Array<pdfService.SearchResultData>) => {
        hits = hits + results.length;
        if (first.length === 0 && results.length > 0) {
          first = 'p' + results[0].pageIndex + ':' + results[0].contextString;
        }
        return false;
      });
      let cjkHits: number = 0;
      try {
        await doc.searchKey('测试', (results: Array<pdfService.SearchResultData>) => {
          cjkHits = cjkHits + results.length;
          return false;
        });
      } catch (_cjkError) {
      }
      this.addLine('search', hits > 0, 'alphaHits=' + hits + '; cjkHits=' + cjkHits + '; first=' + first, Date.now() - t5);
    } catch (error) {
      this.addLine('search', false, String(error), Date.now() - t5);
    }

    const t6: number = Date.now();
    try {
      const encProbe: pdfService.PdfDocument = new pdfService.PdfDocument();
      const isEnc: boolean = encProbe.isEncrypted(encPath);
      let wrongResult: string = 'n/a';
      try {
        wrongResult = String(encProbe.loadDocument(encPath, 'wrong-password'));
      } catch (wrongError) {
        wrongResult = 'throw:' + String(wrongError);
      }
      const okDoc: pdfService.PdfDocument = new pdfService.PdfDocument();
      const okLoad: pdfService.ParseResult = okDoc.loadDocument(encPath, 'manxia123');
      const encPages: number = okLoad === pdfService.ParseResult.PARSE_SUCCESS ? okDoc.getPageCount() : -1;
      try {
        okDoc.releaseDocument();
      } catch (_r1) {
      }
      try {
        encProbe.releaseDocument();
      } catch (_r2) {
      }
      this.addLine('encrypted', isEnc && okLoad === pdfService.ParseResult.PARSE_SUCCESS, 'isEncrypted=' + isEnc + '; wrongPw=' + wrongResult + '; correctPw=' + String(okLoad) + '; pages=' + encPages, Date.now() - t6);
    } catch (error) {
      this.addLine('encrypted', false, String(error), Date.now() - t6);
    }

    const t7: number = Date.now();
    try {
      const imgDoc: pdfService.PdfDocument = new pdfService.PdfDocument();
      const imgLoad: pdfService.ParseResult = imgDoc.loadDocument(imgPath);
      let imgTextLen: number = -1;
      if (imgLoad === pdfService.ParseResult.PARSE_SUCCESS) {
        imgTextLen = imgDoc.getPage(0).getTextContent().length;
      }
      try {
        imgDoc.releaseDocument();
      } catch (_r3) {
      }
      this.addLine('text_extract_image_only', imgLoad === pdfService.ParseResult.PARSE_SUCCESS && imgTextLen === 0, 'load=' + String(imgLoad) + '; textLen=' + imgTextLen, Date.now() - t7);
    } catch (error) {
      this.addLine('text_extract_image_only', false, String(error), Date.now() - t7);
    }

    const t8: number = Date.now();
    try {
      const pm: image.PixelMap = doc.getPage(0).getPagePixelMap();
      const info = pm.getImageInfoSync();
      const w: number = info.size.width;
      const h: number = info.size.height;
      pm.release();
      this.addLine('page_pixelmap', w > 0, 'size=' + w + 'x' + h, Date.now() - t8);
    } catch (error) {
      this.addLine('page_pixelmap', false, String(error), Date.now() - t8);
    }

    const t9: number = Date.now();
    try {
      const outPath: string = textPath.substring(0, textPath.lastIndexOf('/')) + '/probe_saved_copy.pdf';
      try {
        SafeFileUtils.unlinkSync(outPath);
      } catch (_unlinkError2) {
      }
      const saved: boolean = doc.saveDocument(outPath);
      const exists: boolean = SafeFileUtils.accessSync(outPath);
      const size: number = exists ? SafeFileUtils.statSync(outPath).size : 0;
      this.addLine('save_document', saved && exists && size > 0, 'saved=' + saved + '; exists=' + exists + '; size=' + size, Date.now() - t9);
    } catch (error) {
      this.addLine('save_document', false, String(error), Date.now() - t9);
    }

    try {
      doc.releaseDocument();
    } catch (_releaseError) {
    }

    const t10: number = Date.now();
    try {
      this.probeViewerPath = textPath;
      const viewLoad: pdfService.ParseResult = await this.probeController.loadDocument(textPath);
      this.probeViewLoaded = viewLoad === pdfService.ParseResult.PARSE_SUCCESS;
      let viewPages: number = -1;
      try {
        viewPages = this.probeController.getPageCount();
      } catch (_pageError) {
      }
      this.addLine('view_load', this.probeViewLoaded && viewPages > 0, 'ParseResult=' + String(viewLoad) + '; viewPages=' + viewPages, Date.now() - t10);
    } catch (error) {
      this.addLine('view_load', false, String(error), Date.now() - t10);
    }

    const t11: number = Date.now();
    try {
      this.probeController.setPageZoom(1.5);
      const zoom: number = this.probeController.getPageZoom();
      this.probeController.setPageContinuous(true);
      const continuous: boolean = this.probeController.isPageContinuous();
      this.probeController.setPageFit(pdfService.PageFit.FIT_WIDTH);
      const fit: number = this.probeController.getPageFit();
      this.addLine('view_zoom_fit', zoom > 1.0, 'zoom=' + zoom + '; continuous=' + continuous + '; fit=' + String(fit), Date.now() - t11);
    } catch (error) {
      this.addLine('view_zoom_fit', false, String(error), Date.now() - t11);
    }

    const t12: number = Date.now();
    try {
      const annotatedPath: string = textPath.substring(0, textPath.lastIndexOf('/')) + '/probe_annotated.pdf';
      try {
        SafeFileUtils.unlinkSync(annotatedPath);
      } catch (_unlinkAnn) {
      }
      this.probeController.setHighlightText(0, ['alpha'], 0xFFFF0000);
      const annSaveRet: number = await this.probeController.saveDocument(annotatedPath);
      const annExists: boolean = SafeFileUtils.accessSync(annotatedPath);
      const annSize: number = annExists ? SafeFileUtils.statSync(annotatedPath).size : 0;
      this.addLine('view_annotation_save', annExists && annSize > 0, 'saveRet=' + annSaveRet + '; exists=' + annExists + '; size=' + annSize, Date.now() - t12);
    } catch (error) {
      this.addLine('view_annotation_save', false, String(error), Date.now() - t12);
    }

    const t16: number = Date.now();
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const coverDir: string = ctx.filesDir + '/ebook_covers';
      try {
        SafeFileUtils.mkdirSync(coverDir, true);
      } catch (_mkdirCover) {
      }
      const coverTarget: string = coverDir + '/probe_cover.webp';
      const coverResult = await EBookCoverExtractor.extractCover(textPath, coverTarget);
      this.addLine('pdf_cover_extract', coverResult.success && coverResult.coverPath.length > 0, 'success=' + coverResult.success + '; path=' + coverResult.coverPath + '; err=' + (coverResult.errorMessage ?? ''), Date.now() - t16);
    } catch (error) {
      this.addLine('pdf_cover_extract', false, String(error), Date.now() - t16);
    }

    const t15: number = Date.now();
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const targetDir: string = ctx.filesDir + '/ebooks';
      try {
        SafeFileUtils.mkdirSync(targetDir, true);
      } catch (_mkdirEbook) {
      }
      const target: string = targetDir + '/probe_native_pdf.pdf';
      try {
        SafeFileUtils.unlinkSync(target);
      } catch (_unlinkNative) {
      }
      SafeFileUtils.copyFileSyncStrict(textPath, target);
      const parser = EBookParserFactory.createParser(target);
      if (parser === null) {
        this.addLine('import_native_pdf', false, 'parser null', Date.now() - t15);
      } else {
        const ebook = await parser.parse();
        ebook.isFavorite = true;
        await EBookDataManager.getInstance().saveEBook(ebook);
        this.addLine('import_native_pdf', true, 'bookId=' + ebook.id + '; title=' + ebook.metadata.title + '; format=' + String(ebook.format), Date.now() - t15);
      }
    } catch (error) {
      this.addLine('import_native_pdf', false, String(error), Date.now() - t15);
    }

    const t14: number = Date.now();
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const indexService = PdfTextIndexService.getInstance();
      const built: boolean = await indexService.buildIndex(ctx, 'probe_book', textPath);
      const alphaHits = await indexService.search(ctx, 'probe_book', 'alpha');
      const cjkHits = await indexService.search(ctx, 'probe_book', '测试');
      this.addLine('text_index', built && alphaHits.length > 0 && cjkHits.length > 0, 'built=' + built + '; alphaHits=' + alphaHits.length + '; cjkHits=' + cjkHits.length + '; snippet=' + (cjkHits.length > 0 ? cjkHits[0].snippet : ''), Date.now() - t14);
    } catch (error) {
      this.addLine('text_index', false, String(error), Date.now() - t14);
    }

    const t13: number = Date.now();
    try {
      const filesDir: string = textPath.substring(0, textPath.lastIndexOf('/')).replace('/pdf_probe', '');
      const bigPath: string = filesDir + '/transfer_uploads/files/1787247455185_tx_1787247418626_440642_阿衰单行本全集70册整合版本.pdf';
      if (!SafeFileUtils.accessSync(bigPath)) {
        this.addLine('large_file', false, 'not found: ' + bigPath, Date.now() - t13);
        return;
      }
      const bigStat = SafeFileUtils.statSync(bigPath);
      const bigDoc: pdfService.PdfDocument = new pdfService.PdfDocument();
      const bigLoadStart: number = Date.now();
      const bigLoad: pdfService.ParseResult = bigDoc.loadDocument(bigPath);
      const bigLoadMs: number = Date.now() - bigLoadStart;
      let bigPages: number = -1;
      let bigTextLen: number = -1;
      let bigRoots: number = -1;
      let bigWidth: number = -1;
      if (bigLoad === pdfService.ParseResult.PARSE_SUCCESS) {
        bigPages = bigDoc.getPageCount();
        try {
          bigRoots = bigDoc.getRootBookmarks().length;
        } catch (_rootError) {
        }
        try {
          bigTextLen = bigDoc.getPage(0).getTextContent().length;
        } catch (_textError) {
        }
        try {
          const bigPm: image.PixelMap = bigDoc.getPage(0).getPagePixelMap();
          bigWidth = bigPm.getImageInfoSync().size.width;
          bigPm.release();
        } catch (_pmError) {
        }
      }
      try {
        bigDoc.releaseDocument();
      } catch (_releaseBig) {
      }
      this.addLine('large_file', bigLoad === pdfService.ParseResult.PARSE_SUCCESS, 'bytes=' + bigStat.size + '; loadMs=' + bigLoadMs + '; pages=' + bigPages + '; outlineRoots=' + bigRoots + '; pageTextLen=' + bigTextLen + '; pmWidth=' + bigWidth, Date.now() - t13);
    } catch (error) {
      this.addLine('large_file', false, String(error), Date.now() - t13);
    }
  }

  @Builder
  buildResultList() {
    List({ space: 6, scroller: this.probeScroller }) {
      ForEach(this.probeResults, (item: PdfProbeLine) => {
        ListItem() {
          Column({ space: 2 }) {
            Row({ space: 8 }) {
              Text(item.pass ? 'PASS' : 'FAIL')
                .fontSize(12)
                .fontColor(item.pass ? $r('app.color.color_success') : $r('app.color.color_error'))
                .fontWeight(FontWeight.Bold)
              Text(item.name)
                .fontSize(13)
                .fontColor($r('app.color.text_primary'))
                .fontWeight(FontWeight.Medium)
              Text(item.elapsedMs + 'ms')
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')

            Text(item.detail)
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(6)
          .borderRadius(6)
          .backgroundColor($r('app.color.background_secondary'))
        }
      }, (item: PdfProbeLine, index: number) => item.name + '_' + index)
    }
    .width('100%')
    .height(420)
    .scrollBar(BarState.Auto)
  }

  build() {
    NavDestination() {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Button() {
            SymbolGlyph($r('sys.symbol.arrow_left'))
              .fontSize(18)
              .fontColor([$r('app.color.text_primary')])
          }
          .width(36)
          .height(36)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            if (this.probePathStack) {
              this.probePathStack.pop();
            }
          })

          Text('返回测试管理')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')

        Text('PDF Kit 能力探针')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')

        Text(this.probeRunning ? '正在执行...' : ('完成: ' + this.probeResults.length + ' 项, viewEvents=' + this.probeViewEvents))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')

        if (this.probeViewerPath.length > 0) {
          PdfView({
            controller: this.probeController,
            pageFit: pdfService.PageFit.FIT_PAGE,
            isContinuous: false,
            showScroll: false,
            pageLayout: pdfService.PageLayout.LAYOUT_SINGLE
          })
            .width('100%')
            .height(180)
        }

        this.buildResultList()
      }
      .width('100%')
      .height('100%')
      .padding(12)
      .backgroundColor($r('app.color.background_primary'))
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.probePathStack = context.pathStack;
    })
  }
}
