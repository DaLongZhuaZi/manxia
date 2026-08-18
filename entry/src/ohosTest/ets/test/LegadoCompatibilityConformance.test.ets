import { describe, it, expect } from '@ohos/hypium';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { LegadoCompatibilityCompiler } from '../../../main/ets/Framework/Novel/LegadoCompatibilityCompiler';
import { LargeFileJSONParser } from '../../../main/ets/Framework/Novel/LargeFileJSONParser';
import {
  LegadoRuleAnalyzer,
  LegadoRuleJsExecutionBinding
} from '../../../main/ets/Framework/Novel/LegadoRuleAnalyzer';
import { getLegadoJsEngine, JsContext } from '../../../main/ets/Framework/Novel/LegadoJsEngine';
import { getLegadoJsApiContractRegistry } from '../../../main/ets/Framework/Novel/LegadoJsApiContractRegistry';
import { LegadoUrlAnalyzer } from '../../../main/ets/Framework/Novel/LegadoUrlAnalyzer';
import { LegadoRequestPlanner, LegadoTransportRouter } from '../../../main/ets/Framework/Novel/LegadoRequestPipeline';
import { LegadoTraceSerializer } from '../../../main/ets/Framework/Novel/LegadoTraceSerializer';
import { LegadoV2SourceExecutor, LegadoWorkflowOrchestrator } from '../../../main/ets/Framework/Novel/LegadoWorkflowOrchestrator';
import { LegadoContentSemantics } from '../../../main/ets/Framework/Novel/LegadoContentSemantics';
import { LegadoExecutionCancellationToken } from '../../../main/ets/Framework/Novel/LegadoExecutionCancellation';
import { buildLegadoImageVirtualSourceRecordName } from '../../../main/ets/Framework/Novel/LegadoMangaSourceBridge';
import { RequestHeaderEntry, RequestHeaders } from '../../../main/ets/Framework/Cache/ImageCacheManager';
import {
  MangaAssetLoadContextInput,
  MangaAssetLoadContextResolver
} from '../../../main/ets/components/MangaAssetLoadContextResolver';
import { MangaAssetRequestFactory } from '../../../main/ets/Framework/Reader/MangaAssetRequestFactory';
import { MangaAssetLoadReason } from '../../../main/ets/Framework/Reader/MangaAssetTypes';
import { ImageSourceType, MangaImageRequestHeader, MangaPage } from '../../../main/ets/Models/MangaModels';
import {
  LegadoBookSource,
  LegadoBookSourceType,
  LegadoChapter
} from '../../../main/ets/Framework/Novel/LegadoSourceTypes';
import {
  LegadoSourceScriptResult,
  LegadoSourceScriptRuntimeBase
} from '../../../main/ets/Framework/Novel/LegadoSourceScriptRuntime';
import {
  LegadoExecutionErrorCode,
  LegadoExecutionTrace,
  LegadoBridgeTrace,
  LegadoFinalUrlObservation,
  LegadoCapability,
  LegadoRequestHeader,
  LegadoRequestOptionTrace,
  LegadoRequestDisposition,
  LegadoResponseHeader,
  LegadoTransportKind,
  LegadoWorkflowKind,
  RequestSpec,
  ResponseEnvelope
} from '../../../main/ets/Framework/Novel/LegadoCompatibilityTypes';

class FixtureSourceScriptRuntime extends LegadoSourceScriptRuntimeBase {
  private readonly fixtureResult: LegadoSourceScriptResult;
  lastCode: string = '';

  constructor(fixtureResult: LegadoSourceScriptResult) {
    super();
    this.fixtureResult = fixtureResult;
  }

  async execute(
    _source: LegadoBookSource,
    code: string,
    _workflowVariables: Map<string, string>,
    _cancellationToken?: LegadoExecutionCancellationToken
  ): Promise<LegadoSourceScriptResult> {
    this.lastCode = code;
    return this.fixtureResult;
  }
}

function emitCompatibilityTrace(trace: LegadoExecutionTrace): void {
  hilog.info(
    0xD001,
    'LegadoCompat',
    'MANXIA_LEGADO_TRACE:%{public}s',
    LegadoTraceSerializer.toRedactedJson(trace)
  );
}

function emitWireObservationTrace(
  statusCode: number,
  wireProtocol: string,
  sawUserAgent: boolean,
  sawCustomHeader: boolean,
  sawKeepAlive: boolean,
  sawConnection: boolean,
  sawCacheControl: boolean,
  userAgentSha256: string,
  keepAliveSha256: string,
  connectionSha256: string,
  cacheControlSha256: string,
  acceptEncodingSha256: string
): void {
  hilog.info(
    0xD001,
    'LegadoCompat',
    'MANXIA_LEGADO_WIRE_TRACE:transport=http;status=%{public}d;protocol=%{public}s;userAgent=%{public}s;customHeader=%{public}s;keepAlive=%{public}s;connection=%{public}s;cacheControl=%{public}s;userAgentSha256=%{public}s;keepAliveSha256=%{public}s;connectionSha256=%{public}s;cacheControlSha256=%{public}s;acceptEncodingSha256=%{public}s',
    statusCode,
    wireProtocol,
    String(sawUserAgent),
    String(sawCustomHeader),
    String(sawKeepAlive),
    String(sawConnection),
    String(sawCacheControl),
    userAgentSha256,
    keepAliveSha256,
    connectionSha256,
    cacheControlSha256,
    acceptEncodingSha256
  );
}

function extractFixtureJsonString(body: string, fieldName: string): string {
  const marker = `"${fieldName}":"`;
  const valueStart = body.indexOf(marker);
  if (valueStart < 0) {
    return '';
  }
  const contentStart = valueStart + marker.length;
  const valueEnd = body.indexOf('"', contentStart);
  if (valueEnd <= contentStart) {
    return '';
  }
  return body.substring(contentStart, valueEnd);
}

function extractFixtureHeaderValueSha256(body: string, headerName: string): string {
  const marker = `"name":"${headerName}","valueSha256":"`;
  const valueStart = body.indexOf(marker);
  if (valueStart < 0) {
    return '';
  }
  const contentStart = valueStart + marker.length;
  const valueEnd = body.indexOf('"', contentStart);
  if (valueEnd - contentStart !== 64) {
    return '';
  }
  const value = body.substring(contentStart, valueEnd);
  return /^[0-9a-f]{64}$/.test(value) ? value : '';
}

function emitConnectionObservationTrace(
  firstStatusCode: number,
  secondStatusCode: number,
  firstProtocol: string,
  secondProtocol: string,
  connectionReused: boolean,
  firstAcceptEncoding: boolean,
  secondAcceptEncoding: boolean
): void {
  hilog.info(
    0xD001,
    'LegadoCompat',
    'MANXIA_LEGADO_CONNECTION_TRACE:transport=http;firstStatus=%{public}d;secondStatus=%{public}d;firstProtocol=%{public}s;secondProtocol=%{public}s;connectionReused=%{public}s;firstAcceptEncoding=%{public}s;secondAcceptEncoding=%{public}s',
    firstStatusCode,
    secondStatusCode,
    firstProtocol,
    secondProtocol,
    String(connectionReused),
    String(firstAcceptEncoding),
    String(secondAcceptEncoding)
  );
}

function emitCompressionObservationTrace(statusCode: number, decodedFixtureMarker: boolean): void {
  hilog.info(
    0xD001,
    'LegadoCompat',
    'MANXIA_LEGADO_COMPRESSION_TRACE:transport=http;status=%{public}d;decodedFixtureMarker=%{public}s',
    statusCode,
    String(decodedFixtureMarker)
  );
}

function emitTlsObservationTrace(
  statusCode: number,
  tlsProtocol: string,
  httpVersion: string,
  alpnPresent: boolean,
  cipherPresent: boolean
): void {
  hilog.info(
    0xD001,
    'LegadoCompat',
    'MANXIA_LEGADO_TLS_TRACE:transport=http;status=%{public}d;tlsProtocol=%{public}s;httpVersion=%{public}s;alpnPresent=%{public}s;cipherPresent=%{public}s',
    statusCode,
    tlsProtocol,
    httpVersion,
    String(alpnPresent),
    String(cipherPresent)
  );
}

export default function legadoCompatibilityConformanceTest() {
  describe('LegadoCompatibilityConformance', () => {
    it('preservesUtf8RawDocumentsAcrossOneByteChunks', 0, async () => {
      const firstRaw = '{"bookSourceUrl":"https://fixture.test/utf8-one","bookSourceName":"汉字😀","bookSourceType":0,"extension":{"escaped":"a\\\"b","nested":[1,{"value":"跨块"}]}}';
      const secondRaw = '{"bookSourceUrl":"https://fixture.test/utf8-two","bookSourceName":"第二源🍀","bookSourceType":0,"unknown":[{"value":"仍然完整"}]}';
      const sourcePackage = `\uFEFF[${firstRaw},${secondRaw}]`;
      const bytes = util.TextEncoder.create('utf-8').encodeInto(sourcePackage);
      const documents = await LargeFileJSONParser.parseUtf8ChunksForConformance(bytes, 1);
      expect(documents.length).assertEqual(2);
      expect(documents[0]).assertEqual(firstRaw);
      expect(documents[1]).assertEqual(secondRaw);

      const compiled = await new LegadoCompatibilityCompiler().compileOne(documents[0]);
      expect(compiled !== null).assertTrue();
      if (compiled !== null) {
        expect(compiled.raw.rawJson).assertEqual(firstRaw);
        expect(compiled.source.bookSourceName).assertEqual('汉字😀');
      }
    });

    it('preservesRawDocumentAndExternalType', 0, async () => {
      const raw = '{"bookSourceUrl":"https://fixture.test/source","bookSourceName":"fixture","bookSourceType":4,"weight":19,"extensionField":{"keep":true}}';
      const compiler = new LegadoCompatibilityCompiler();
      const compiled = await compiler.compileOne(raw);
      expect(compiled !== null).assertTrue();
      if (compiled !== null) {
        expect(compiled.raw.rawJson).assertEqual(raw);
        expect(compiled.source.bookSourceType).assertEqual(4);
        expect(compiled.source.weight).assertEqual(19);
        expect(compiled.status).assertEqual('unsupported');
      }
    });

    it('retainsAllRelevantUrlOptionFields', 0, async () => {
      const analyzer = new LegadoUrlAnalyzer('http://fixture.test', 'https://fixture.test/source');
      const parsed = await analyzer.analyzeUrlAsync(
        'http://fixture.test/search,{"method":"POST","body":"q={{key}}","webView":true,"webJs":"document.title","serverID":7,"webViewDelayTime":25,"type":"epub"}',
        'keyword',
        1
      );
      expect(parsed.method).assertEqual('POST');
      expect(parsed.body || '').assertContain('keyword');
      expect(parsed.useWebView === true).assertTrue();
      expect(parsed.serverId || 0).assertEqual(7);
      expect(parsed.webViewDelayTime || 0).assertEqual(25);
      expect(parsed.responseType || '').assertEqual('epub');
    });

    it('classifiesUnknownJsApiAsUnsupported', 0, () => {
      const assessment = getLegadoJsApiContractRegistry().assess('java.unregisteredTransport("x")');
      expect(assessment.hasBlockingContract).assertTrue();
      expect(assessment.contracts.length > 0).assertTrue();
    });

    it('declaresToNumChapterAsSupportedLegadoBridgeApi', 0, () => {
      const assessment = getLegadoJsApiContractRegistry().assess('java.toNumChapter("第十二章")');
      expect(assessment.hasBlockingContract).assertFalse();
      expect(assessment.contracts.length).assertEqual(1);
      expect(assessment.contracts[0].api).assertEqual('java.toNumChapter');
    });

    it('declaresImplementedVariableAndTimeApisAsSupported', 0, () => {
      const assessment = getLegadoJsApiContractRegistry().assess(
        "java.put('time', java.timeFormatUTC(0, 'yyyy-MM-dd', 8)); java.base64Decode('YQ==')"
      );
      expect(assessment.hasBlockingContract).assertFalse();
      expect(assessment.contracts.length).assertEqual(3);
    });

    it('declaresDefaultTimeFormatAsSupportedLegadoBridgeApi', 0, () => {
      const assessment = getLegadoJsApiContractRegistry().assess('java.timeFormat(0)');
      expect(assessment.hasBlockingContract).assertFalse();
      expect(assessment.contracts.length).assertEqual(1);
      expect(assessment.contracts[0].api).assertEqual('java.timeFormat');
    });

    it('doesNotRejectTheImplementedRhinoJavaPackageSubset', 0, () => {
      const assessment = getLegadoJsApiContractRegistry().assess(
        "Packages.java.lang.System.currentTimeMillis(); new java.lang.String('A').getBytes('UTF-8'); " +
        "Packages.java.lang.System.err.println('diagnostic'); " +
        "Packages.android.util.Base64.encodeToString([65], Packages.android.util.Base64.NO_WRAP); java.get('bid')"
      );
      expect(assessment.hasBlockingContract).assertFalse();
      expect(assessment.contracts.length).assertEqual(6);
      expect(assessment.contracts[0].api).assertEqual('java.lang.System.currentTimeMillis');
      expect(assessment.contracts[4].api).assertEqual('android.util.Base64.NO_WRAP');
      expect(assessment.contracts[5].api).assertEqual('java.get');
    });

    it('doesNotRejectTheImplementedJavaImporterCipherSubset', 0, () => {
      const assessment = getLegadoJsApiContractRegistry().assess(
        "var ji=new JavaImporter(); ji.importPackage(Packages.java.lang,Packages.javax.crypto.spec,Packages.javax.crypto,Packages.java.util); " +
        "with(ji){var packed=Base64.getDecoder().decode('fixture'); var key=new SecretKeySpec(String('fixture-key').getBytes(),'AES'); " +
        "var iv=new IvParameterSpec(Arrays.copyOfRange(packed,0,16)); var cipher=Cipher.getInstance('AES/CBC/PKCS5Padding'); " +
        "cipher.init(2,key,iv); String(cipher.doFinal(packed));}"
      );
      expect(assessment.hasBlockingContract).assertFalse();
      let hasCryptoPackage: boolean = false;
      let hasCryptoSpecPackage: boolean = false;
      for (let index = 0; index < assessment.contracts.length; index++) {
        if (assessment.contracts[index].api === 'javax.crypto') {
          hasCryptoPackage = true;
        }
        if (assessment.contracts[index].api === 'javax.crypto.spec') {
          hasCryptoSpecPackage = true;
        }
      }
      expect(hasCryptoPackage).assertTrue();
      expect(hasCryptoSpecPackage).assertTrue();
    });

    it('doesNotTreatAnEndpointFileNameAsAnAndroidApi', 0, () => {
      const assessment = getLegadoJsApiContractRegistry().assess(
        "const endpoint = 'https://fixture.test/android.php'; java.get('bid'); // android.unregistered()"
      );
      expect(assessment.hasBlockingContract).assertFalse();
      expect(assessment.contracts.length).assertEqual(1);
      expect(assessment.contracts[0].api).assertEqual('java.get');
    });

    it('doesNotBlockImplementedToastAndJsoupPackageApis', 0, () => {
      const assessment = getLegadoJsApiContractRegistry().assess(
        "java.toast('ready'); org.jsoup.Jsoup.parse('<p>fixture</p>')"
      );
      expect(assessment.hasBlockingContract).assertFalse();
      expect(assessment.contracts.length).assertEqual(2);
      expect(assessment.contracts[0].api).assertEqual('java.toast');
      expect(assessment.contracts[1].api).assertEqual('org.jsoup.Jsoup.parse');
    });

    it('resolvesRuntimeBackedSourceFieldsBeforeStringMembers', 0, () => {
      const assessment = getLegadoJsApiContractRegistry().assess(
        "source.bookSourceName.includes('fixture'); source.bookSourceComment.split('|'); source.bookSourceType"
      );
      expect(assessment.hasBlockingContract).assertFalse();
      expect(assessment.contracts.length).assertEqual(3);
      expect(assessment.contracts[0].api).assertEqual('source.bookSourceName');
      expect(assessment.contracts[1].api).assertEqual('source.bookSourceComment');
      expect(assessment.contracts[2].api).assertEqual('source.bookSourceType');
    });

    it('declaresVerifiedHmacBridgeAsSupportedWithOriginalArgumentOrder', 0, () => {
      const assessment = getLegadoJsApiContractRegistry().assess("java.HMacHex('payload', 'HmacSHA256', 'secret')");
      expect(assessment.hasBlockingContract).assertFalse();
      expect(assessment.contracts.length).assertEqual(1);
      expect(assessment.contracts[0].api).assertEqual('java.HMacHex');
    });

    it('classifiesHeadlessJsExecutionAsWebViewUnavailable', 0, async () => {
      // Instrumentation has no ArkWeb component. JS semantics are asserted by
      // the real ArkWeb fixture ability; this guards the headless boundary.
      const result = await getLegadoJsEngine().execute("java.md5Encode('abc')");
      expect(result.success).assertFalse();
      expect(result.error || '').assertEqual('WEBVIEW_NOT_READY');
    });

    it('keepsTopLevelJsRuleResultOutsideVariableScope', 0, async () => {
      const analyzer = new LegadoUrlAnalyzer('https://fixture.test/book', 'https://fixture.test/source');
      analyzer.setVariable('result', 'stale-result');
      const parsed = await analyzer.analyzeUrlAsync('@js:result');
      // AnalyzeUrl seeds top-level JS `result` from the full rule string, then
      // still runs normal absolute URL resolution, as AnalyzeUrl.kt does.
      expect(parsed.url).assertEqual('https://fixture.test/@js:result');
    });

    it('doesNotBlockTheVerifiedXiaomiReaderApiSubset', 0, () => {
      const assessment = getLegadoJsApiContractRegistry().assess(
        "java.ajax(result); java.base64Decode('YQ=='); java.getString('$.time'); java.put('time', java.timeFormatUTC(0, 'yyyy-MM-dd', 8))"
      );
      expect(assessment.hasBlockingContract).assertFalse();
      expect(assessment.contracts.length).assertEqual(5);
    });

    it('parsesStaticExploreKindsWithOriginalSeparatorsAndJson', 0, async () => {
      const textRaw = '{"bookSourceUrl":"https://fixture.test/explore-text","bookSourceName":"fixture-explore-text","bookSourceType":0,"exploreUrl":"第一类::/one&&第二类::/two\\n第三类"}';
      const jsonRaw = '{"bookSourceUrl":"https://fixture.test/explore-json","bookSourceName":"fixture-explore-json","bookSourceType":0,"exploreUrl":"[{\\"title\\":\\"JSON分类\\",\\"url\\":\\"/json\\"}]"}';
      const compiler = new LegadoCompatibilityCompiler();
      const textCompiled = await compiler.compileOne(textRaw);
      const jsonCompiled = await compiler.compileOne(jsonRaw);
      expect(textCompiled !== null).assertTrue();
      expect(jsonCompiled !== null).assertTrue();
      if (textCompiled !== null) {
        const textKinds = new LegadoWorkflowOrchestrator(textCompiled).getExploreKinds();
        expect(textKinds.length).assertEqual(3);
        expect(textKinds[0].title).assertEqual('第一类');
        expect(textKinds[1].url).assertEqual('/two');
        expect(textKinds[2].url).assertEqual('');
      }
      if (jsonCompiled !== null) {
        const jsonKinds = new LegadoWorkflowOrchestrator(jsonCompiled).getExploreKinds();
        expect(jsonKinds.length).assertEqual(1);
        expect(jsonKinds[0].title).assertEqual('JSON分类');
      }
    });

    it('executesDynamicExploreKindsBeforeParsingJson', 0, async () => {
      const raw = '{"bookSourceUrl":"https://fixture.test/explore-js","bookSourceName":"fixture-explore-js","bookSourceType":0,"exploreUrl":"@js:JSON.stringify([{title:\\"动态分类\\",url:\\"/dynamic\\"}])"}';
      const compiled = await new LegadoCompatibilityCompiler().compileOne(raw);
      expect(compiled !== null).assertTrue();
      if (compiled !== null) {
        const fixtureResult = new LegadoSourceScriptResult(
          true,
          '[{"title":"动态分类","url":"/dynamic"}]',
          LegadoExecutionErrorCode.NONE,
          '',
          [],
          []
        );
        const runtime = new FixtureSourceScriptRuntime(fixtureResult);
        const workflow = new LegadoWorkflowOrchestrator(compiled, runtime);
        expect(workflow.getExploreKinds().length).assertEqual(0);
        const kinds = await workflow.getExploreKindsAsync();
        expect(runtime.lastCode.startsWith('@js:')).assertFalse();
        expect(kinds.length).assertEqual(1);
        expect(kinds[0].title).assertEqual('动态分类');
        expect(kinds[0].url).assertEqual('/dynamic');
        const trace = workflow.getLastTrace();
        expect(trace !== null).assertTrue();
        if (trace !== null) {
          expect(trace.outputSummary).assertEqual('explore-kinds:1');
          emitCompatibilityTrace(trace);
        }
      }
    });

    it('doesNotExposeDynamicExploreScriptWhenExecutionFails', 0, async () => {
      const raw = '{"bookSourceUrl":"https://fixture.test/explore-js-failure","bookSourceName":"fixture-explore-js-failure","bookSourceType":0,"exploreUrl":"@js:var privateRule = \\"must-not-render\\"; throw new Error(privateRule)"}';
      const compiled = await new LegadoCompatibilityCompiler().compileOne(raw);
      expect(compiled !== null).assertTrue();
      if (compiled !== null) {
        const fixtureResult = new LegadoSourceScriptResult(
          false,
          '',
          LegadoExecutionErrorCode.RULE,
          'SCRIPT_RUNTIME',
          [],
          []
        );
        const workflow = new LegadoWorkflowOrchestrator(
          compiled,
          new FixtureSourceScriptRuntime(fixtureResult)
        );
        expect(workflow.getExploreKinds().length).assertEqual(0);
        let failure = '';
        try {
          await workflow.getExploreKindsAsync();
        } catch (error) {
          failure = String(error);
        }
        expect(failure).assertContain('SCRIPT_RUNTIME');
        expect(failure.includes('must-not-render')).assertFalse();
      }
    });

    it('usesCompleteSearchRuleWhenExploreListSelectorIsEmpty', 0, async () => {
      const raw = '{"bookSourceUrl":"http://127.0.0.1:18765","bookSourceName":"fixture-explore-search-fallback","bookSourceType":0,"exploreUrl":"http://127.0.0.1:18765/search","ruleExplore":{"name":"$.must_not_be_used"},"ruleSearch":{"bookList":"$.items","bookUrl":"$.url","name":"$.name","author":"$.author"}}';
      const compiled = await new LegadoCompatibilityCompiler().compileOne(raw);
      expect(compiled !== null).assertTrue();
      if (compiled !== null) {
        const workflow = new LegadoWorkflowOrchestrator(compiled);
        const result = await workflow.explore(compiled.source.exploreUrl || '', 1);
        expect(result.books.length).assertEqual(1);
        expect(result.books[0].name).assertEqual('fixture-book');
        expect(result.books[0].author).assertEqual('fixture-author');
        const trace = workflow.getLastTrace();
        expect(trace !== null).assertTrue();
        if (trace !== null) {
          expect(trace.outputSummary).assertContain('rule=search-fallback');
          emitCompatibilityTrace(trace);
        }
      }
    });

    it('usesStableDistinctDatabaseNamesForSameNamedImageSources', 0, () => {
      const first = buildLegadoImageVirtualSourceRecordName(
        '快看漫画',
        'legado.image.0123456789abcdef'
      );
      const second = buildLegadoImageVirtualSourceRecordName(
        '快看漫画',
        'legado.image.fedcba9876543210'
      );
      expect(first === second).assertFalse();
      expect(first).assertContain('快看漫画');
      expect(first).assertContain('0123456789abcdef');
      expect(second).assertContain('fedcba9876543210');
    });

    it('mapsImagePageHeadersIntoTypedTransportFields', 0, () => {
      const page: MangaPage = {
        id: 'fixture-image-page',
        index: 0,
        sourceType: ImageSourceType.NETWORK,
        imagePath: 'https://fixture.test/image.jpg',
        imageUrl: 'https://fixture.test/image.jpg',
        isLoaded: false,
        requestHeaders: []
      } as MangaPage;
      page.requestHeaders?.push({ name: 'User-Agent', value: 'fixture-image-agent' } as MangaImageRequestHeader);
      page.requestHeaders?.push({ name: 'Referer', value: 'https://fixture.test/chapter' } as MangaImageRequestHeader);
      page.requestHeaders?.push({ name: 'Origin', value: 'https://fixture.test/path' } as MangaImageRequestHeader);
      page.requestHeaders?.push({ name: 'Cookie', value: 'fixture=image' } as MangaImageRequestHeader);
      page.requestHeaders?.push({ name: 'Accept', value: 'image/webp' } as MangaImageRequestHeader);
      page.requestHeaders?.push({ name: 'X-Fixture-Image', value: 'custom-value' } as MangaImageRequestHeader);

      const baseHeaders: RequestHeaders = {} as RequestHeaders;
      baseHeaders.extraHeaders = [
        { name: 'Referer', value: 'https://fixture.test/stale' } as RequestHeaderEntry,
        { name: 'X-Base-Image', value: 'base-value' } as RequestHeaderEntry
      ];
      const input = new MangaAssetLoadContextInput();
      input.networkHeaders = baseHeaders;
      input.useLegadoV2ImageTransport = true;
      const context = new MangaAssetLoadContextResolver().build(
        page,
        0,
        MangaAssetLoadReason.VISIBLE,
        input
      );
      const headers = context.headers;
      expect(headers !== undefined).assertTrue();
      if (headers !== undefined) {
        expect(headers.userAgent).assertEqual('fixture-image-agent');
        expect(headers.referer).assertEqual('https://fixture.test/chapter');
        expect(headers.origin).assertEqual('https://fixture.test/path');
        expect(headers.cookie).assertEqual('fixture=image');
        expect(headers.accept).assertEqual('image/webp');
        const extras = headers.extraHeaders || [];
        expect(extras.length).assertEqual(2);
        expect(extras[0].name).assertEqual('X-Base-Image');
        expect(extras[1].name).assertEqual('X-Fixture-Image');
      }
      expect(context.useLegadoV2ImageTransport).assertTrue();
      const request = new MangaAssetRequestFactory().build(page, 0, context);
      expect(request.useLegadoV2ImageTransport).assertTrue();
    });

    it('redactsTraceSecretsAndBodies', 0, () => {
      const request = new RequestSpec(
        'trace-1',
        'https://fixture.test/source?token=secret-token',
        LegadoWorkflowKind.SEARCH,
        'https://fixture.test/search?token=secret-token',
        'POST',
        'password=plain-text',
        [new LegadoRequestHeader('Cookie', 'session=secret-cookie')],
        'UTF-8',
        0,
        '',
        true,
        false,
        '',
        '',
        0,
        0,
        '',
        'follow',
        [new LegadoRequestOptionTrace('method', LegadoRequestDisposition.EXECUTED, 'POST')]
      );
      const response = new ResponseEnvelope(
        'trace-1',
        'response-body-must-not-appear',
        'https://fixture.test/final?access_token=secret-token',
        LegadoFinalUrlObservation.UNOBSERVABLE,
        200,
        request.headers,
        [new LegadoResponseHeader('Set-Cookie', 'session=secret-cookie')],
        true,
        [request.url],
        LegadoTransportKind.HTTP,
        1,
        LegadoExecutionErrorCode.NONE,
        ''
      );
      const trace = new LegadoExecutionTrace(
        'trace-1',
        request.sourceUrl,
        LegadoWorkflowKind.SEARCH,
        request,
        response,
        ['page'],
        'search:1'
      );
      const serialized = LegadoTraceSerializer.toRedactedJson(trace);
      expect(serialized).assertContain('[REDACTED]');
      expect(serialized.includes('secret-token')).assertFalse();
      expect(serialized.includes('secret-cookie')).assertFalse();
      expect(serialized.includes('response-body-must-not-appear')).assertFalse();
      expect(serialized.includes('password=plain-text')).assertFalse();
    });

    it('retainsNestedBridgeFailureEvidenceWithoutRawSecrets', 0, () => {
      const request = new RequestSpec(
        'bridge-trace-1',
        'https://fixture.test/source',
        LegadoWorkflowKind.EXPLORE,
        'legado://explore-kinds',
        'SCRIPT',
        '',
        [],
        'UTF-8',
        0,
        '',
        false,
        true,
        '',
        '',
        0,
        0,
        'text',
        'not_applicable',
        []
      );
      const response = new ResponseEnvelope(
        'bridge-trace-1',
        '',
        'legado://explore-kinds',
        LegadoFinalUrlObservation.OBSERVED,
        0,
        [],
        [],
        false,
        ['legado://explore-kinds'],
        LegadoTransportKind.ARK_WEB,
        0,
        LegadoExecutionErrorCode.NETWORK,
        'SCRIPT_NETWORK'
      );
      const trace = new LegadoExecutionTrace(
        'bridge-trace-1',
        request.sourceUrl,
        LegadoWorkflowKind.EXPLORE,
        request,
        response,
        [],
        'explore-kinds:failed:network',
        [new LegadoBridgeTrace(
          'http-1',
          'http',
          'https://fixture.test/data?token=secret-token',
          'GET',
          false,
          0,
          0,
          ['User-Agent', 'X-Source-Auth'],
          'HTTP_FAILED: secret-token'
        )]
      );
      const serialized = LegadoTraceSerializer.toRedactedJson(trace);
      expect(serialized).assertContain('"bridgeTraces"');
      expect(serialized).assertContain('"statusCode":0');
      expect(serialized).assertContain('X-Source-Auth');
      expect(serialized).assertContain('[REDACTED]');
      expect(serialized.includes('secret-token')).assertFalse();
    });

    it('persistsOnlyHashedNetworkEvidence', 0, async () => {
      const request = new RequestSpec(
        'network-evidence-1',
        'https://fixture.test/source',
        LegadoWorkflowKind.BOOK_INFO,
        'https://fixture.test/book/path?token=secret-token',
        'GET',
        '',
        [new LegadoRequestHeader('User-Agent', 'fixture-user-agent')],
        '',
        0,
        '',
        false,
        false,
        '',
        '',
        0,
        0,
        '',
        'follow',
        []
      );
      const response = new ResponseEnvelope(
        'network-evidence-1',
        'fixture-response-body',
        'https://fixture.test/book/path',
        LegadoFinalUrlObservation.OBSERVED,
        200,
        request.headers,
        [new LegadoResponseHeader('Content-Type', 'text/html; charset=UTF-8')],
        false,
        [request.url, 'https://fixture.test/book/path'],
        LegadoTransportKind.HTTP,
        1,
        LegadoExecutionErrorCode.NONE,
        ''
      );
      const trace = new LegadoExecutionTrace(
        'network-evidence-1',
        request.sourceUrl,
        LegadoWorkflowKind.BOOK_INFO,
        request,
        response,
        [],
        'book_info:fixture'
      );
      const evidence = await LegadoTraceSerializer.toNetworkTraceEvidence(trace);
      expect(evidence.requestTargetSha256.length).assertEqual(64);
      expect(evidence.requestUserAgentSha256.length).assertEqual(64);
      expect(evidence.responseContentType).assertEqual('text/html');
      expect(evidence.redirectCount).assertEqual(1);
      expect(evidence.requestTargetSha256.includes('secret-token')).assertFalse();
      expect(evidence.requestUserAgentSha256.includes('fixture-user-agent')).assertFalse();
    });

    it('usesForwardedFixtureForHttpTransport', 0, async () => {
      const raw = '{"bookSourceUrl":"http://127.0.0.1:18765","bookSourceName":"fixture-http","bookSourceType":0,"enabledCookieJar":true,"searchUrl":"http://127.0.0.1:18765/header-post,{\\"method\\":\\"POST\\",\\"body\\":\\"q={{key}}\\",\\"headers\\":{\\"X-Legado-Header\\":\\"fixture-header\\"},\\"retry\\":1}","ruleSearch":{"bookList":"$.items","bookUrl":"$.url","name":"$.name"}}';
      const compiled = await new LegadoCompatibilityCompiler().compileOne(raw);
      expect(compiled !== null).assertTrue();
      if (compiled !== null) {
        const planner = new LegadoRequestPlanner(compiled);
        const request = await planner.plan(LegadoWorkflowKind.SEARCH, compiled.source.searchUrl || '', 'fixture');
        let plannedCookieJar = '';
        for (let index = 0; index < request.headers.length; index++) {
          const header = request.headers[index];
          if (header.name.toLowerCase() === 'cookiejar') {
            plannedCookieJar = header.value;
            break;
          }
        }
        expect(plannedCookieJar).assertEqual('1');
        const response = await new LegadoTransportRouter().execute(request);
        expect(response.statusCode).assertEqual(200);
        expect(response.body).assertContain('fixture-header-post');
        expect(response.body).assertContain('fixture-header');
        expect(response.body).assertContain('application/x-www-form-urlencoded');
        expect(response.body).assertContain('"cookieJar":""');
        let observedCookieJar = false;
        let observedContentType = false;
        for (let index = 0; index < response.requestHeaders.length; index++) {
          const header = response.requestHeaders[index];
          if (header.name.toLowerCase() === 'cookiejar') {
            observedCookieJar = header.value === '1';
          }
          if (header.name.toLowerCase() === 'content-type') {
            observedContentType = true;
          }
        }
        expect(observedCookieJar).assertTrue();
        expect(observedContentType).assertFalse();
        expect(response.finalUrlObservation).assertEqual('unobservable');
        const trace = new LegadoExecutionTrace(
          request.traceId,
          request.sourceUrl,
          request.workflow,
          request,
          response,
          [],
          'fixture-header-post'
        );
        emitCompatibilityTrace(trace);
      }
    });

    it('recordsWireObservationForEffectiveHttpTransport', 0, async () => {
      const raw = '{"bookSourceUrl":"http://127.0.0.1:18765","bookSourceName":"fixture-wire-observation","bookSourceType":0,"searchUrl":"http://127.0.0.1:18765/wire-observation,{\\"method\\":\\"GET\\",\\"headers\\":{\\"X-Legado-Header\\":\\"fixture-wire-header\\"}}","ruleSearch":{"bookList":"$.items","bookUrl":"$.url","name":"$.name"}}';
      const compiled = await new LegadoCompatibilityCompiler().compileOne(raw);
      expect(compiled !== null).assertTrue();
      if (compiled !== null) {
        const request = await new LegadoRequestPlanner(compiled).plan(
          LegadoWorkflowKind.SEARCH,
          compiled.source.searchUrl || '',
          'fixture'
        );
        const response = await new LegadoTransportRouter().execute(request);
        expect(response.statusCode).assertEqual(200);
        expect(response.body).assertContain('fixture-wire-observation-v1');
        expect(response.body).assertContain('"name":"x-legado-header"');
        const protocolMarker = '"protocol":"';
        const protocolStart = response.body.indexOf(protocolMarker);
        expect(protocolStart >= 0).assertTrue();
        const protocolValueStart = protocolStart + protocolMarker.length;
        const protocolValueEnd = response.body.indexOf('"', protocolValueStart);
        expect(protocolValueEnd > protocolValueStart).assertTrue();
        const wireProtocol = response.body.substring(protocolValueStart, protocolValueEnd);
        const sawUserAgent = response.body.includes('"name":"user-agent"');
        const sawCustomHeader = response.body.includes('"name":"x-legado-header"');
        const sawKeepAlive = response.body.includes('"name":"keep-alive"');
        const sawConnection = response.body.includes('"name":"connection"');
        const sawCacheControl = response.body.includes('"name":"cache-control"');
        const userAgentSha256 = extractFixtureHeaderValueSha256(response.body, 'user-agent');
        const keepAliveSha256 = extractFixtureHeaderValueSha256(response.body, 'keep-alive');
        const connectionSha256 = extractFixtureHeaderValueSha256(response.body, 'connection');
        const cacheControlSha256 = extractFixtureHeaderValueSha256(response.body, 'cache-control');
        const acceptEncodingSha256 = extractFixtureHeaderValueSha256(response.body, 'accept-encoding');
        expect(userAgentSha256.length).assertEqual(64);
        expect(keepAliveSha256.length).assertEqual(64);
        expect(connectionSha256.length).assertEqual(64);
        expect(cacheControlSha256.length).assertEqual(64);
        expect(acceptEncodingSha256.length).assertEqual(64);
        expect(acceptEncodingSha256).assertEqual('d1f08cf77c6b1dcfe5a23c46922c328ef023f6d04713cf07f4fdcf8a43aee241');
        emitWireObservationTrace(
          response.statusCode,
          wireProtocol,
          sawUserAgent,
          sawCustomHeader,
          sawKeepAlive,
          sawConnection,
          sawCacheControl,
          userAgentSha256,
          keepAliveSha256,
          connectionSha256,
          cacheControlSha256,
          acceptEncodingSha256
        );

        const connectionUrl = 'http://127.0.0.1:18765/connection-observation,{"method":"GET"}';
        const firstConnectionRequest = await new LegadoRequestPlanner(compiled).plan(
          LegadoWorkflowKind.SEARCH,
          connectionUrl,
          'fixture'
        );
        const secondConnectionRequest = await new LegadoRequestPlanner(compiled).plan(
          LegadoWorkflowKind.SEARCH,
          connectionUrl,
          'fixture'
        );
        const transport = new LegadoTransportRouter();
        const firstConnectionResponse = await transport.execute(firstConnectionRequest);
        const secondConnectionResponse = await transport.execute(secondConnectionRequest);
        expect(firstConnectionResponse.statusCode).assertEqual(200);
        expect(secondConnectionResponse.statusCode).assertEqual(200);
        const firstFingerprint = extractFixtureJsonString(firstConnectionResponse.body, 'connectionFingerprint');
        const secondFingerprint = extractFixtureJsonString(secondConnectionResponse.body, 'connectionFingerprint');
        const firstProtocol = extractFixtureJsonString(firstConnectionResponse.body, 'protocol');
        const secondProtocol = extractFixtureJsonString(secondConnectionResponse.body, 'protocol');
        expect(firstFingerprint.length).assertEqual(64);
        expect(secondFingerprint.length).assertEqual(64);
        expect(firstProtocol.length > 0).assertTrue();
        expect(secondProtocol.length > 0).assertTrue();
        emitConnectionObservationTrace(
          firstConnectionResponse.statusCode,
          secondConnectionResponse.statusCode,
          firstProtocol,
          secondProtocol,
          firstFingerprint === secondFingerprint,
          firstConnectionResponse.body.includes('"name":"accept-encoding"'),
          secondConnectionResponse.body.includes('"name":"accept-encoding"')
        );

        const compressedUrl = 'http://127.0.0.1:18765/compressed-observation,{"method":"GET"}';
        const compressedRequest = await new LegadoRequestPlanner(compiled).plan(
          LegadoWorkflowKind.SEARCH,
          compressedUrl,
          'fixture'
        );
        const compressedResponse = await transport.execute(compressedRequest);
        expect(compressedResponse.statusCode).assertEqual(200);
        const decodedFixtureMarker = compressedResponse.body.includes('fixture-compressed-observation-v1');
        expect(decodedFixtureMarker).assertTrue();
        emitCompressionObservationTrace(compressedResponse.statusCode, decodedFixtureMarker);
      }
    });

    it('usesLegadoTlsCompatibilityForSelfSignedFixture', 0, async () => {
      const raw = '{"bookSourceUrl":"https://127.0.0.1:18766","bookSourceName":"fixture-tls-observation","bookSourceType":0,"searchUrl":"https://127.0.0.1:18766/tls-observation,{\\"method\\":\\"GET\\"}","ruleSearch":{"bookList":"$.items","bookUrl":"$.url","name":"$.name"}}';
      const compiled = await new LegadoCompatibilityCompiler().compileOne(raw);
      expect(compiled !== null).assertTrue();
      if (compiled !== null) {
        const request = await new LegadoRequestPlanner(compiled).plan(
          LegadoWorkflowKind.SEARCH,
          compiled.source.searchUrl || '',
          'fixture'
        );
        const response = await new LegadoTransportRouter().execute(request);
        expect(response.statusCode).assertEqual(200);
        expect(response.body).assertContain('fixture-tls-observation-v1');
        const tlsProtocol = extractFixtureJsonString(response.body, 'protocol');
        const httpVersion = extractFixtureJsonString(response.body, 'httpVersion');
        const alpnPresent = response.body.includes('"alpnPresent":true');
        const cipherPresent = response.body.includes('"cipherPresent":true');
        expect(tlsProtocol.length > 0).assertTrue();
        expect(httpVersion.length > 0).assertTrue();
        expect(cipherPresent).assertTrue();
        emitTlsObservationTrace(response.statusCode, tlsProtocol, httpVersion, alpnPresent, cipherPresent);
      }
    });

    it('injectsLegadoDefaultUserAgentUnlessSourceOverridesIt', 0, async () => {
      const defaultRaw = '{"bookSourceUrl":"http://127.0.0.1:18765","bookSourceName":"fixture-default-ua","bookSourceType":0,"searchUrl":"http://127.0.0.1:18765/search","ruleSearch":{"bookList":"$.items","bookUrl":"$.url","name":"$.name"}}';
      const defaultCompiled = await new LegadoCompatibilityCompiler().compileOne(defaultRaw);
      expect(defaultCompiled !== null).assertTrue();
      if (defaultCompiled !== null) {
        const defaultRequest = await new LegadoRequestPlanner(defaultCompiled).plan(
          LegadoWorkflowKind.SEARCH,
          defaultCompiled.source.searchUrl || '',
          'fixture'
        );
        let defaultUserAgent = '';
        for (let index = 0; index < defaultRequest.headers.length; index++) {
          const header = defaultRequest.headers[index];
          if (header.name.toLowerCase() === 'user-agent') {
            defaultUserAgent = header.value;
            break;
          }
        }
        expect(defaultUserAgent).assertEqual(
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36'
        );
        let defaultTracePresent = false;
        for (let index = 0; index < defaultRequest.optionTrace.length; index++) {
          const item = defaultRequest.optionTrace[index];
          if (item.option === 'defaultUserAgent' && item.disposition === LegadoRequestDisposition.EXECUTED) {
            defaultTracePresent = true;
            break;
          }
        }
        expect(defaultTracePresent).assertTrue();
      }

      const overrideRaw = '{"bookSourceUrl":"http://127.0.0.1:18765","bookSourceName":"fixture-override-ua","bookSourceType":0,"header":"{\\"User-Agent\\":\\"fixture-source-agent\\"}","searchUrl":"http://127.0.0.1:18765/search","ruleSearch":{"bookList":"$.items","bookUrl":"$.url","name":"$.name"}}';
      const overrideCompiled = await new LegadoCompatibilityCompiler().compileOne(overrideRaw);
      expect(overrideCompiled !== null).assertTrue();
      if (overrideCompiled !== null) {
        const overrideRequest = await new LegadoRequestPlanner(overrideCompiled).plan(
          LegadoWorkflowKind.SEARCH,
          overrideCompiled.source.searchUrl || '',
          'fixture'
        );
        let overriddenUserAgent = '';
        for (let index = 0; index < overrideRequest.headers.length; index++) {
          const header = overrideRequest.headers[index];
          if (header.name.toLowerCase() === 'user-agent') {
            overriddenUserAgent = header.value;
            break;
          }
        }
        expect(overriddenUserAgent).assertEqual('fixture-source-agent');
      }
    });

    it('usesFirstCssMatchForSingleUrlsAndKeepsSiblingTocPages', 0, async () => {
      const analyzer = new LegadoRuleAnalyzer();
      analyzer.setContent(
        '<article class="fixture-card"><a href="/book/multiple-links">fixture-first</a><a href="/book/incorrect">fixture-later</a></article>',
        'http://127.0.0.1:18765/search/multiple-links'
      );
      const textValues = await analyzer.getStringAsync('class.fixture-card@tag.a@href');
      const singleUrl = await analyzer.getUrlStringAsync('class.fixture-card@tag.a@href');
      expect(textValues).assertEqual('/book/multiple-links\n/book/incorrect');
      expect(singleUrl).assertEqual('/book/multiple-links');

      const raw = '{"bookSourceUrl":"http://127.0.0.1:18765","bookSourceName":"fixture-multiple-url-semantics","bookSourceType":0,"searchUrl":"http://127.0.0.1:18765/search/multiple-links","ruleSearch":{"bookList":"class.fixture-card","bookUrl":"tag.a@href","name":"tag.a@text"},"ruleBookInfo":{"name":"class.fixture-info@tag.h1@text","tocUrl":"class.fixture-toc@tag.a@href"},"ruleToc":{"chapterList":"class.fixture-chapter","chapterName":"tag.a@text","chapterUrl":"tag.a@href","nextTocUrl":"class.fixture-next@tag.a@href"}}';
      const compiled = await new LegadoCompatibilityCompiler().compileOne(raw);
      expect(compiled !== null).assertTrue();
      if (compiled !== null) {
        const workflow = new LegadoWorkflowOrchestrator(compiled);
        const search = await workflow.search('fixture');
        expect(search.books.length).assertEqual(1);
        expect(search.books[0].bookUrl).assertEqual('http://127.0.0.1:18765/book/multiple-links');
        const info = await workflow.getBookInfo(search.books[0].bookUrl);
        expect(info.book !== null).assertTrue();
        if (info.book !== null) {
          expect(info.book.tocUrl).assertEqual('http://127.0.0.1:18765/toc/multiple/root');
          const toc = await workflow.getChapterList(info.book);
          expect(toc.chapters.length).assertEqual(3);
          expect(toc.chapters[0].title).assertEqual('fixture-root');
          expect(toc.chapters[1].title).assertEqual('fixture-one');
          expect(toc.chapters[2].title).assertEqual('fixture-two');
          if (toc.trace !== null) {
            emitCompatibilityTrace(toc.trace);
          }
        }
      }
    });

    it('projectsJsTocObjectsAndPreservesCnCuFieldsInLargeHtml', 0, async () => {
      const source: LegadoBookSource = {
        bookSourceUrl: 'https://fixture.test/image-source',
        bookSourceName: 'fixture-image-js-toc',
        bookSourceType: LegadoBookSourceType.IMAGE,
        bookSourceComment: 'function getChapterList(cn,cu,ci){var names=java.getStringList(cn);var urls=java.getStringList(cu);var infos=ci===""?[]:java.getStringList(ci);var list=[];for(var i=0;i<names.length;i++){list.push({cn:names[i],cu:urls[i],ci:infos[i]||""});}return list;}'
      };
      const analyzer = new LegadoRuleAnalyzer();
      analyzer.setJsExecutionBinding(new LegadoRuleJsExecutionBinding(source, undefined, undefined, '', 1));
      const filler = 'fixture-padding-'.repeat(5000);
      analyzer.setContent(
        '<section class="fixture-list"><article><a href="/chapter/one">One</a></article>' +
        '<article><a href="/chapter/two">Two</a></article></section>' + filler,
        'https://fixture.test/image-source/book'
      );
      const directNames = analyzer.getStringList('class.fixture-list@tag.article@tag.a@text');
      const directUrls = analyzer.getStringList('class.fixture-list@tag.article@tag.a@href');
      hilog.info(0xD001, 'LegadoCompat', 'TOC_FIELD_FIXTURE directNames=%{public}d directUrls=%{public}d', directNames.length, directUrls.length);
      expect(directNames.length).assertEqual(2);
      expect(directUrls.length).assertEqual(2);

      // This ability has no ArkWeb component, so keep the headless contract
      // deterministic: validate the post-JS JSON projection independently.
      // Source-comment evaluation and java.getStringList are covered by the
      // real ArkWeb conformance ability, where a WebView is actually present.
      const projectedJson = '[{"cn":"One","cu":"/chapter/one","ci":""},{"cn":"Two","cu":"/chapter/two","ci":""}]';
      analyzer.setContent(projectedJson, 'https://fixture.test/image-source/book');
      const elements = await analyzer.getElementsAsync('$.[*]');
      expect(elements.length).assertEqual(2);

      const first = new LegadoRuleAnalyzer();
      first.setContent(elements[0], 'https://fixture.test/image-source/book');
      expect(await first.getStringAsync('cn')).assertEqual('One');
      expect(await first.getUrlStringAsync('cu')).assertEqual('/chapter/one');
      expect(await first.getStringAsync('ci')).assertEqual('');
    });

    it('keepsCssChildCombinatorsNarrowInLargeDocumentFallback', 0, async () => {
      const analyzer = new LegadoRuleAnalyzer();
      analyzer.setContent(
        '<html><body><div class="warpper"><div class="o_all"><div class="o_content"><div><table><tbody>' +
        '<tr><td>header</td></tr><tr><td>expected-one</td></tr><tr><td>expected-two</td></tr>' +
        '</tbody></table></div></div></div></div><table><tbody><tr><td>unrelated</td></tr></tbody></table></body></html>',
        'https://fixture.test/search'
      );
      const rows = await analyzer.getElementsAsync(
        'body > div.warpper > div.o_all > div.o_content > div > table > tbody > tr!0'
      );
      expect(rows.length).assertEqual(2);
      expect(rows[0].includes('expected-one')).assertTrue();
      expect(rows[1].includes('expected-two')).assertTrue();
    });

    it('createsImplicitTableBodyForCssChildCombinators', 0, async () => {
      const analyzer = new LegadoRuleAnalyzer();
      analyzer.setContent(
        '<html><body><div class="warpper"><div class="o_all"><div class="o_content"><div><table>' +
        '<tr><td>header</td></tr><tr><td>implicit-one</td></tr><tr><td>implicit-two</td></tr>' +
        '</table></div></div></div></div><table><tr><td>unrelated</td></tr></table></body></html>',
        'https://fixture.test/search'
      );
      const rows = await analyzer.getElementsAsync(
        'body > div.warpper > div.o_all > div.o_content > div > table > tbody > tr!0'
      );
      expect(rows.length).assertEqual(2);
      expect(rows[0].includes('implicit-one')).assertTrue();
      expect(rows[1].includes('implicit-two')).assertTrue();
    });

    it('keepsLegacyExcludeIndexInBridgeCssChains', 0, async () => {
      const analyzer = new LegadoRuleAnalyzer();
      analyzer.setContent(
        '<html><body><div class="container"><li>navigation</li>' +
        '<li><a href="/book/one">expected-one</a></li>' +
        '<li><a href="/book/two">expected-two</a></li>' +
        '</div></body></html>',
        'https://fixture.test/search'
      );
      expect(analyzer.getHtmlBridge() !== null).assertTrue();
      const rows = await analyzer.getElementsAsync('class.container@tag.li!0');
      expect(rows.length).assertEqual(2);
      expect(rows[0].includes('expected-one')).assertTrue();
      expect(rows[1].includes('expected-two')).assertTrue();
    });

    it('reportsOnlySanitizedDomCandidateForSimpleContentChains', 0, async () => {
      const analyzer = new LegadoRuleAnalyzer();
      analyzer.setContent(
        '<html><body><section class="fixture-content"><p>first paragraph</p><p>second paragraph</p></section></body></html>',
        'https://fixture.test/content'
      );
      const probe = analyzer.getSimpleCssChainBridgeProbe('class.fixture-content@tag.p@text');
      expect(probe.status).assertEqual('available');
      expect(probe.candidate).assertEqual('first paragraph\nsecond paragraph');

      const indexedProbe = analyzer.getSimpleCssChainBridgeProbe('class.fixture-content@tag.p!0@text');
      expect(indexedProbe.status).assertEqual('not_applicable');
      expect(indexedProbe.candidate).assertEqual('');
    });

    it('keepsOnlyDirectTextNodesForLegacyContentChains', 0, () => {
      // JSoup Element.textNodes() excludes text held by descendant elements,
      // but retains direct siblings around inline and self-closing nodes.
      const analyzer = new LegadoRuleAnalyzer();
      analyzer.setContent(
        '<section id="fixture-textnodes"> first <span>nested-one</span> second<br/> third<!--ignored--><em>nested-two</em> </section>',
        'http://127.0.0.1:18765/content/textnodes'
      );
      const extracted = analyzer.getString('id.fixture-textnodes@textNodes');
      expect(extracted).assertEqual('first\nsecond\nthird');
      expect(extracted.includes('nested-one')).assertFalse();
      expect(extracted.includes('nested-two')).assertFalse();
    });

    it('keepsExpandedAbsoluteUrlTemplateAsSearchBookUrl', 0, async () => {
      const analyzer = new LegadoRuleAnalyzer();
      analyzer.setContent('{"bookId":"fixture-book-id"}', 'https://fixture.test/search');
      const value = await analyzer.getUrlStringAsync(
        'https://fixture.test/book/info?bookId={{$.bookId}}&mode=v2'
      );
      expect(value).assertEqual('https://fixture.test/book/info?bookId=fixture-book-id&mode=v2');
    });

    it('resolvesBareJsonListFieldAtCurrentDocumentScope', 0, () => {
      // BookList.setContent(item) makes a bare field resolve from the current
      // item. The real ArkWeb fixture covers the following JS postfix.
      const analyzer = new LegadoRuleAnalyzer();
      analyzer.setContent('{"sourceId":"fixture-source-id"}', 'https://fixture.test/search');
      const value = analyzer.getString('sourceId');
      expect(value).assertEqual('fixture-source-id');
    });

    it('resolvesBareJsonPutValueFromCurrentObject', 0, async () => {
      const analyzer = new LegadoRuleAnalyzer();
      analyzer.setContent('{"id":"fixture-book-id","nested":{"id":"fixture-nested-id"}}', 'https://fixture.test/book');

      const result = await analyzer.getStringAsync('@put:{bid:id}$.id');
      expect(result).assertEqual('fixture-book-id');
      expect(analyzer.getVariableValue('bid')).assertEqual('fixture-book-id');

      const nestedResult = analyzer.getString('@put:{nestedBid:nested.id}$.id');
      expect(nestedResult).assertEqual('fixture-book-id');
      expect(analyzer.getVariableValue('nestedBid')).assertEqual('fixture-nested-id');
    });

    it('keepsCssPutValueSemanticsOutsideJson', 0, async () => {
      const analyzer = new LegadoRuleAnalyzer();
      analyzer.setContent('<article id="fixture-css-id">fixture</article>', 'https://fixture.test/book');

      const result = await analyzer.getStringAsync('@put:{cssId:tag.article@id}tag.article@text');
      expect(result).assertEqual('fixture');
      expect(analyzer.getVariableValue('cssId')).assertEqual('fixture-css-id');

      analyzer.setContent('<article data-id="fixture-data-id">fixture</article>', 'https://fixture.test/book');
      const directDataAttribute = await analyzer.getStringAsync('tag.article@data-id');
      expect(directDataAttribute).assertEqual('fixture-data-id');
      await analyzer.getStringAsync('@put:{dataId:tag.article@data-id}tag.article@text');
      expect(analyzer.getVariableValue('dataId')).assertEqual('fixture-data-id');
    });

    it('preservesMultilinePostfixJavaScriptBookUrlAtCompileBoundary', 0, async () => {
      const raw = '{"bookSourceUrl":"http://127.0.0.1:18765","bookSourceName":"fixture-postfix-js-book-url","bookSourceType":0,"searchUrl":"http://127.0.0.1:18765/search","ruleSearch":{"bookList":"$.items","bookUrl":"$.url@js:\\nresult","name":"$.name"}}';
      const compiled = await new LegadoCompatibilityCompiler().compileOne(raw);
      expect(compiled !== null).assertTrue();
      if (compiled !== null) {
        const searchRule = compiled.source.ruleSearch;
        expect(searchRule !== undefined).assertTrue();
        if (searchRule !== undefined) {
          expect(searchRule.bookUrl).assertEqual('$.url@js:\nresult');
        }
      }
    });

    it('runsFixtureSearchInfoTocAndContentWorkflow', 0, async () => {
      const raw = '{"bookSourceUrl":"http://127.0.0.1:18765","bookSourceName":"fixture-workflow","bookSourceType":0,"searchUrl":"http://127.0.0.1:18765/search","ruleSearch":{"bookList":"$.items","bookUrl":"$.url","name":"$.name","author":"$.author"},"ruleBookInfo":{"name":"$.name","author":"$.author","tocUrl":"$.toc","downloadUrls":"$.download"},"ruleToc":{"chapterList":"$.chapters","chapterName":"$.name","chapterUrl":"$.url"},"ruleContent":{"title":"$.title","content":"$.content"}}';
      const compiled = await new LegadoCompatibilityCompiler().compileOne(raw);
      expect(compiled !== null).assertTrue();
      if (compiled !== null) {
        const workflow = new LegadoWorkflowOrchestrator(compiled);
        const search = await workflow.search('fixture');
        expect(search.books.length).assertEqual(1);
        const info = await workflow.getBookInfo(search.books[0].bookUrl);
        expect(info.book !== null).assertTrue();
        if (info.book !== null) {
          expect(info.downloadCandidates.length).assertEqual(1);
          const toc = await workflow.getChapterList(info.book);
          expect(toc.chapters.length).assertEqual(1);
          const content = await workflow.getContent(toc.chapters[0]);
          expect(content.content).assertContain('fixture-content');
          expect(content.title).assertEqual('fixture-chapter');
          if (content.trace !== null) {
            emitCompatibilityTrace(content.trace);
          }
        }
      }
    });

    it('preservesSearchUrlOptionCarrierUntilBookInfoDispatch', 0, async () => {
      const raw = '{"bookSourceUrl":"http://127.0.0.1:18765","bookSourceName":"fixture-request-carrier","bookSourceType":0,"searchUrl":"http://127.0.0.1:18765/search/request-carrier","ruleSearch":{"bookList":"$.items","bookUrl":"$.url","name":"$.name"},"ruleBookInfo":{"name":"$.name","author":"$.author","tocUrl":"$.toc"}}';
      const compiled = await new LegadoCompatibilityCompiler().compileOne(raw);
      expect(compiled !== null).assertTrue();
      if (compiled !== null) {
        const workflow = new LegadoWorkflowOrchestrator(compiled);
        const search = await workflow.search('fixture');
        expect(search.books.length).assertEqual(1);
        const result = search.books[0];
        expect(result.bookUrl).assertEqual('http://127.0.0.1:18765/book/request-carrier');
        expect(result.requestUrlTemplate !== undefined).assertTrue();
        if (result.requestUrlTemplate !== undefined) {
          expect(result.requestUrlTemplate).assertContain('X-Legado-Carrier');
        }
        const info = await workflow.getBookInfo(
          result.bookUrl,
          undefined,
          result.variable,
          result.requestUrlTemplate
        );
        expect(info.book !== null).assertTrue();
        if (info.trace !== null) {
          expect(info.trace.request.headers.some((header: LegadoRequestHeader): boolean =>
            header.name === 'X-Legado-Carrier'
          )).assertTrue();
        }
      }
    });

    it('rehydratesSearchBookVariableInFreshExecutorForBookInfo', 0, async () => {
      const raw = '{"bookSourceUrl":"http://127.0.0.1:18765","bookSourceName":"fixture-variable-carrier","bookSourceType":0,"searchUrl":"http://127.0.0.1:18765/search/variable-carrier","ruleSearch":{"bookList":"$.items","bookUrl":"@put:{fixtureToc:toc}$.url","name":"$.name"},"ruleBookInfo":{"name":"$.name","author":"$.author","tocUrl":"http://127.0.0.1:18765{{fixtureToc}}"}}';
      const compiled = await new LegadoCompatibilityCompiler().compileOne(raw);
      expect(compiled !== null).assertTrue();
      if (compiled !== null) {
        const searchExecutor = new LegadoV2SourceExecutor(compiled);
        const search = await searchExecutor.searchWithTrace('fixture');
        expect(search.books.length).assertEqual(1);
        const searchBook = search.books[0];
        const searchBookVariable = searchBook.variable;
        expect(searchBookVariable !== undefined).assertTrue();
        if (searchBookVariable === undefined) {
          return;
        }
        expect(searchBookVariable.length > 0).assertTrue();

        // A distinct executor has no Search-side workflow state. Passing only
        // the selected book snapshot models a rebuilt detail page after the
        // manager's transient carrier maps have been discarded.
        const rehydratedExecutor = new LegadoV2SourceExecutor(compiled);
        expect(rehydratedExecutor.getVariableSnapshot()).assertEqual('{}');
        const info = await rehydratedExecutor.getBookInfoWithTrace(
          searchBook.bookUrl,
          undefined,
          searchBookVariable
        );
        expect(info.book !== null).assertTrue();
        if (info.book !== null) {
          expect(info.book.tocUrl).assertEqual('http://127.0.0.1:18765/toc/1');
        }
        if (info.trace !== null) {
          emitCompatibilityTrace(info.trace);
        }
      }
    });

    it('isolatesSearchBookVariablesAcrossFreshExecutorsForBookInfo', 0, async () => {
      const raw = '{"bookSourceUrl":"http://127.0.0.1:18765","bookSourceName":"fixture-variable-carrier-isolation","bookSourceType":0,"searchUrl":"http://127.0.0.1:18765/search/variable-carrier-isolation","ruleSearch":{"bookList":"$.items","bookUrl":"@put:{fixtureToc:toc}$.url","name":"$.name"},"ruleBookInfo":{"name":"$.name","author":"$.author","tocUrl":"http://127.0.0.1:18765{{fixtureToc}}"}}';
      const compiled = await new LegadoCompatibilityCompiler().compileOne(raw);
      expect(compiled !== null).assertTrue();
      if (compiled === null) {
        return;
      }
      const searchExecutor = new LegadoV2SourceExecutor(compiled);
      const search = await searchExecutor.searchWithTrace('fixture');
      expect(search.books.length).assertEqual(2);
      const alphaBook = search.books[0];
      const betaBook = search.books[1];
      const alphaVariable = alphaBook.variable;
      const betaVariable = betaBook.variable;
      expect(alphaVariable !== undefined).assertTrue();
      expect(betaVariable !== undefined).assertTrue();
      if (alphaVariable === undefined || betaVariable === undefined) {
        return;
      }
      expect(alphaVariable.length > 0).assertTrue();
      expect(betaVariable.length > 0).assertTrue();
      expect(alphaVariable === betaVariable).assertFalse();

      // Run beta first to prove that a later fresh executor for alpha cannot
      // inherit the most recently reconstructed item's variable snapshot.
      const betaExecutor = new LegadoV2SourceExecutor(compiled);
      expect(betaExecutor.getVariableSnapshot()).assertEqual('{}');
      const betaInfo = await betaExecutor.getBookInfoWithTrace(
        betaBook.bookUrl,
        undefined,
        betaVariable
      );
      expect(betaInfo.book !== null).assertTrue();
      if (betaInfo.book !== null) {
        expect(betaInfo.book.tocUrl).assertEqual('http://127.0.0.1:18765/toc/isolation/beta');
      }

      const alphaExecutor = new LegadoV2SourceExecutor(compiled);
      expect(alphaExecutor.getVariableSnapshot()).assertEqual('{}');
      const alphaInfo = await alphaExecutor.getBookInfoWithTrace(
        alphaBook.bookUrl,
        undefined,
        alphaVariable
      );
      expect(alphaInfo.book !== null).assertTrue();
      if (alphaInfo.book !== null) {
        expect(alphaInfo.book.tocUrl).assertEqual('http://127.0.0.1:18765/toc/isolation/alpha');
      }
      if (alphaInfo.trace !== null) {
        emitCompatibilityTrace(alphaInfo.trace);
      }
      if (betaInfo.trace !== null) {
        emitCompatibilityTrace(betaInfo.trace);
      }
    });

    it('mirrorsOriginalBookListFinalizationForSearchOrderDuplicatesAndEmptyUrls', 0, async () => {
      const raw = '{"bookSourceUrl":"http://127.0.0.1:18765","bookSourceName":"fixture-book-list-finalization","bookSourceType":0,"searchUrl":"http://127.0.0.1:18765/search/book-list-finalization","ruleSearch":{"bookList":"-$.items","bookUrl":"$.url","name":"$.name"}}';
      const compiled = await new LegadoCompatibilityCompiler().compileOne(raw);
      expect(compiled !== null).assertTrue();
      if (compiled !== null) {
        const workflow = new LegadoWorkflowOrchestrator(compiled);
        const search = await workflow.search('fixture');
        // Original BookList first removes duplicate bookUrl entries, resolves
        // blank URLs to the effective response URL, then applies '-'.
        expect(search.books.length).assertEqual(3);
        expect(search.books[0].bookUrl).assertEqual('http://127.0.0.1:18765/book/final-last');
        expect(search.books[1].bookUrl).assertEqual('http://127.0.0.1:18765/search/book-list-finalization');
        expect(search.books[2].bookUrl).assertEqual('http://127.0.0.1:18765/book/final-first');
      }
    });

    it('normalizesHtmlSelectorOutputBeforeReaderDelivery', 0, async () => {
      const raw = '{"bookSourceUrl":"http://127.0.0.1:18765","bookSourceName":"fixture-html-content","bookSourceType":0,"ruleContent":{"content":"class.fixture-content@html"}}';
      const compiled = await new LegadoCompatibilityCompiler().compileOne(raw);
      expect(compiled !== null).assertTrue();
      if (compiled !== null) {
        const workflow = new LegadoWorkflowOrchestrator(compiled);
        const chapter: LegadoChapter = {
          id: 'fixture-html-chapter',
          bookUrl: 'http://127.0.0.1:18765/book/1',
          url: 'http://127.0.0.1:18765/content/html',
          title: 'fixture-html-chapter',
          index: 0
        };
        const content = await workflow.getContent(chapter);
        expect(content.content).assertContain('fixture-html-content line');
        expect(content.content).assertContain('fixture-html-second-line');
        expect(content.content.startsWith('　　fixture-html-content line')).assertTrue();
        expect(content.content.includes('<p')).assertFalse();
        expect(content.content.includes('&nbsp;')).assertFalse();
        if (content.trace !== null) {
          expect(content.trace.outputSummary).assertContain('presentation=readable');
          emitCompatibilityTrace(content.trace);
        }
      }
    });

    it('aggregatesEveryOuterHtmlMatchForCssHtmlRule', 0, () => {
      const analyzer = new LegadoRuleAnalyzer();
      analyzer.setContent(
        '<div class="fixture-html-many"><p>first</p><p>second</p></div>',
        'http://127.0.0.1:18765/content/html-many'
      );
      const extracted = analyzer.getString('class.fixture-html-many@tag.p@html');
      expect(extracted.includes('<p>first</p>')).assertTrue();
      expect(extracted.includes('<p>second</p>')).assertTrue();
      // AnalyzeByJSoup serializes Elements.outerHtml() without a separator.
      // A synthetic LF becomes a reader paragraph boundary after formatting,
      // so exact serialization is part of the source-rule contract.
      expect(extracted).assertEqual('<p>first</p><p>second</p>');
    });

    it('preservesStandardCssOuterHtmlAcrossOrFallbackRules', 0, () => {
      const analyzer = new LegadoRuleAnalyzer();
      analyzer.setContent(
        '<main id="vcon"><p>first</p><p>second</p></main><div id="con"><p>fallback</p></div>',
        'http://127.0.0.1:18765/content/css-outer-fallback'
      );
      const extracted = analyzer.getString('#vcon@p@html||#con@html');
      expect(extracted.includes('<p>first</p>')).assertTrue();
      expect(extracted.includes('<p>second</p>')).assertTrue();
      expect(extracted.includes('fallback')).assertFalse();
      const normalized = LegadoContentSemantics.normalizePageContent(
        extracted,
        LegadoBookSourceType.TEXT,
        'http://127.0.0.1:18765/content/css-outer-fallback'
      );
      expect(normalized.startsWith('　　first')).assertTrue();
    });

    it('preservesUpstreamReaderIndentationAndPageBoundaries', 0, () => {
      const normalized = LegadoContentSemantics.normalizePageContent(
        '<p>first paragraph</p><p>second paragraph</p>',
        LegadoBookSourceType.TEXT,
        'http://127.0.0.1:18765/content/indent'
      );
      expect(normalized).assertEqual('　　first paragraph\n　　second paragraph');
      const joined = LegadoContentSemantics.joinNormalizedPages([
        normalized,
        '　　third paragraph'
      ]);
      expect(joined).assertEqual('　　first paragraph\n　　second paragraph\n　　third paragraph');
    });

    it('preservesFullWidthSourceIndentForCssTextExtraction', 0, () => {
      const analyzer = new LegadoRuleAnalyzer();
      analyzer.setContent(
        '<article class="fixture-source-indent"><p>　　first paragraph</p><p>　　second paragraph</p></article>',
        'http://127.0.0.1:18765/content/source-indent'
      );
      const extracted = analyzer.getString('class.fixture-source-indent@tag.p@text');
      expect(extracted.startsWith('　　first paragraph')).assertTrue();
      const normalized = LegadoContentSemantics.normalizePageContent(
        extracted,
        LegadoBookSourceType.TEXT,
        'http://127.0.0.1:18765/content/source-indent'
      );
      expect(normalized.startsWith('　　first paragraph')).assertTrue();
    });

    it('aggregatesAllContentPagesBeforeApplyingReplaceRegex', 0, async () => {
      const raw = '{"bookSourceUrl":"http://127.0.0.1:18765","bookSourceName":"fixture-multipage-content","bookSourceType":0,"ruleContent":{"content":"class.fixture-page@html","nextContentUrl":"id.fixture-next@href","replaceRegex":"##REMOVE_MARKER"}}';
      const compiled = await new LegadoCompatibilityCompiler().compileOne(raw);
      expect(compiled !== null).assertTrue();
      if (compiled !== null) {
        const workflow = new LegadoWorkflowOrchestrator(compiled);
        const chapter: LegadoChapter = {
          id: 'fixture-multipage-chapter',
          bookUrl: 'http://127.0.0.1:18765/book/1',
          url: 'http://127.0.0.1:18765/content/multipage/one',
          title: 'fixture-multipage-chapter',
          index: 0
        };
        const content = await workflow.getContent(chapter);
        expect(content.content).assertContain('fixture-page-one');
        expect(content.content).assertContain('fixture-page-two');
        expect(content.content.includes('REMOVE_MARKER')).assertFalse();
        if (content.trace !== null) {
          expect(content.trace.outputSummary).assertContain('pages=2');
          expect(content.trace.outputSummary).assertContain('replace=applied');
          emitCompatibilityTrace(content.trace);
        }
      }
    });

    it('turnsImageUrlListsIntoReaderImageNodes', 0, () => {
      const content = LegadoContentSemantics.normalizePageContent(
        '/assets/one.webp\nhttps://fixture.test/assets/two.jpg',
        LegadoBookSourceType.IMAGE,
        'http://127.0.0.1:18765/content/image'
      );
      expect(content).assertContain('<img src="http://127.0.0.1:18765/assets/one.webp">');
      expect(content).assertContain('<img src="https://fixture.test/assets/two.jpg">');
    });

    it('blocksUnimplementedImageDecodeInsteadOfSilentlyIgnoringIt', 0, async () => {
      const raw = '{"bookSourceUrl":"https://fixture.test/image-decode","bookSourceName":"fixture-image-decode","bookSourceType":2,"ruleContent":{"content":"body@html","imageDecode":"@js:result"}}';
      const compiled = await new LegadoCompatibilityCompiler().compileOne(raw);
      expect(compiled !== null).assertTrue();
      if (compiled !== null) {
        expect(compiled.status).assertEqual('blocked');
        expect(compiled.capabilityReport.unavailable.includes(LegadoCapability.IMAGE_DECODE)).assertTrue();
      }
    });

    it('blocksFileSourceWithoutV2DownloaderHandoff', 0, async () => {
      const raw = '{"bookSourceUrl":"https://fixture.test/file","bookSourceName":"fixture-file","bookSourceType":3,"searchUrl":"https://fixture.test/search","ruleSearch":{"bookList":"$.items","bookUrl":"$.url","name":"$.name"},"ruleBookInfo":{"downloadUrls":"$.download"}}';
      const compiled = await new LegadoCompatibilityCompiler().compileOne(raw);
      expect(compiled !== null).assertTrue();
      if (compiled !== null) {
        expect(compiled.status).assertEqual('blocked');
        expect(compiled.capabilityReport.unavailable.includes(LegadoCapability.FILE)).assertTrue();
      }
    });

    it('blocksProtectedHtmlBeforeRuleParsing', 0, async () => {
      const raw = '{"bookSourceUrl":"http://127.0.0.1:18765/protected-login","bookSourceName":"fixture-protected-login","bookSourceType":0,"searchUrl":"http://127.0.0.1:18765/protected-login","ruleSearch":{"bookList":"body","bookUrl":"a","name":"h1"}}';
      const compiled = await new LegadoCompatibilityCompiler().compileOne(raw);
      expect(compiled !== null).assertTrue();
      if (compiled !== null) {
        const workflow = new LegadoWorkflowOrchestrator(compiled);
        const result = await workflow.search('fixture');
        expect(result.books.length).assertEqual(0);
        expect(result.trace !== null).assertTrue();
        if (result.trace !== null) {
          expect(result.trace.response.errorCode).assertEqual(LegadoExecutionErrorCode.NEEDS_INTERACTION);
          expect(result.trace.outputSummary).assertContain('protected_response:html_login');
          emitCompatibilityTrace(result.trace);
        }
      }
    });

    it('classifiesLoginAndReviewAsExplicitNonRunnableCapabilities', 0, async () => {
      const loginRaw = '{"bookSourceUrl":"https://fixture.test/login","bookSourceName":"fixture-login","bookSourceType":0,"loginUrl":"https://fixture.test/login"}';
      const reviewRaw = '{"bookSourceUrl":"https://fixture.test/review","bookSourceName":"fixture-review","bookSourceType":0,"ruleReview":{"reviewList":"$.items"}}';
      const compiler = new LegadoCompatibilityCompiler();
      const loginCompiled = await compiler.compileOne(loginRaw);
      const reviewCompiled = await compiler.compileOne(reviewRaw);
      expect(loginCompiled !== null).assertTrue();
      expect(reviewCompiled !== null).assertTrue();
      if (loginCompiled !== null) {
        expect(loginCompiled.status).assertEqual('needs_interaction');
      }
      if (reviewCompiled !== null) {
        expect(reviewCompiled.status).assertEqual('blocked');
        expect(reviewCompiled.capabilityReport.unavailable.includes(LegadoCapability.REVIEW)).assertTrue();
      }
    });

    it('classifiesUnavailableArkWebHostWithoutFallbackToHttp', 0, async () => {
      const raw = '{"bookSourceUrl":"http://127.0.0.1:18765","bookSourceName":"fixture-arkweb","bookSourceType":0,"searchUrl":"http://127.0.0.1:18765/web,{\\"webView\\":true,\\"webJs\\":\\"document.title\\"}","ruleSearch":{"bookList":"body","bookUrl":"a","name":"a"}}';
      const compiled = await new LegadoCompatibilityCompiler().compileOne(raw);
      expect(compiled !== null).assertTrue();
      if (compiled !== null) {
        const planner = new LegadoRequestPlanner(compiled);
        const request = await planner.plan(LegadoWorkflowKind.SEARCH, compiled.source.searchUrl || '');
        const response = await new LegadoTransportRouter().execute(request);
        expect(response.transport).assertEqual(LegadoTransportKind.ARK_WEB);
        expect(response.errorCode).assertEqual(LegadoExecutionErrorCode.WEB_VIEW);
        const trace = new LegadoExecutionTrace(
          request.traceId,
          request.sourceUrl,
          request.workflow,
          request,
          response,
          [],
          'fixture-arkweb-host-unavailable'
        );
        emitCompatibilityTrace(trace);
      }
    });
  });
}
