import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
import { LegadoCompatibilityCompiler } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoCompatibilityCompiler';
import { getCookieStore } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoCookieStore';
import { LegadoRequestPlanner, LegadoTransportRouter } from '../Framework/Novel/LegadoRequestPipeline';
import { LegadoTraceSerializer } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoTraceSerializer';
import { LegadoWebViewComponent } from '../Framework/Novel/LegadoWebViewComponent';
import { getWebViewExecutor } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoWebViewExecutor';
import { getLegadoRuntimeV2 } from '../Framework/Novel/LegadoRuntimeV2';
import type { JsContext, JsExecuteResult } from '../Framework/Novel/LegadoJsEngine';
import type { LegadoBookSource } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoSourceTypes';
import { LegadoRuleAnalyzer, LegadoRuleJsExecutionBinding } from '../Framework/Novel/LegadoRuleAnalyzer';
import { LegadoUrlAnalyzer } from '../Framework/Novel/LegadoUrlAnalyzer';
import { LegadoWorkflowOrchestrator } from '../Framework/Novel/LegadoWorkflowOrchestrator';
import {
  LegadoExecutionErrorCode,
  LegadoExecutionTrace,
  LegadoFinalUrlObservation,
  LegadoTransportKind,
  LegadoWorkflowKind,
  RequestSpec,
  ResponseEnvelope
} from 'manxia_novel/src/main/ets/Framework/Novel/LegadoCompatibilityTypes';

const TAG: string = 'LegadoArkWebFixture';
const LOG_DOMAIN: number = 0xD001;
const FIXTURE_WEB_URL: string = 'http://127.0.0.1:18765/web';
const FIXTURE_COOKIE_ECHO_URL: string = 'http://127.0.0.1:18765/web-cookie-echo';
const FIXTURE_SOURCE_REGEX: string = '/asset/found\\.css$';
const READY_RETRY_DELAY_MS: number = 100;
const READY_RETRY_LIMIT: number = 100;
const TERMINATE_DELAY_MS: number = 300;
const WEB_JS_SUMMARY: string = 'fixture-arkweb-webjs-cookie';
const SOURCE_REGEX_SUMMARY: string = 'fixture-arkweb-source-regex';
const COOKIE_ROUNDTRIP_SUMMARY: string = 'fixture-arkweb-cookie-roundtrip';
const RUNTIME_SCOPE_REPLAY_SUMMARY: string = 'fixture-runtime-scope-replay-isolation';
const RUNTIME_WORKFLOW_BINDING_SUMMARY: string = 'fixture-runtime-workflow-binding-contract';
const RUNTIME_JAVA_API_SUMMARY: string = 'fixture-runtime-java-api-contract';
const RUNTIME_HIGH_FREQUENCY_API_SUMMARY: string = 'fixture-runtime-high-frequency-api-contract';
const RUNTIME_CONTEXT_API_SUMMARY: string = 'fixture-runtime-context-api-contract';
const RUNTIME_NESTED_WEBVIEW_SUMMARY: string = 'fixture-runtime-nested-webview-contract';
const RUNTIME_SYMMETRIC_CRYPTO_SUMMARY: string = 'fixture-runtime-symmetric-crypto-contract';
const RUNTIME_JAVA_IMPORTER_CIPHER_SUMMARY: string = 'fixture-runtime-java-importer-cipher-contract';
const RUNTIME_HMAC_SUMMARY: string = 'fixture-runtime-hmac-contract';
const RUNTIME_POSTFIX_JS_SUMMARY: string = 'fixture-runtime-postfix-js-contract';
const RUNTIME_JSON_PREFIX_JS_SUMMARY: string = 'fixture-runtime-json-prefix-js-contract';
const RUNTIME_TOP_LEVEL_JS_BOOLEAN_SUMMARY: string = 'fixture-runtime-top-level-js-boolean-contract';
const RUNTIME_DYNAMIC_EVAL_PROBE_SUMMARY: string = 'fixture-runtime-dynamic-eval-probe';
const RUNTIME_TOC_JS_OBJECT_SUMMARY: string = 'fixture-runtime-toc-js-object-projection';
const BOOK_INFO_INIT_TRANSITION_SUMMARY: string = 'fixture-book-info-init-content-transition';
const RUNTIME_SCOPE_SOURCE_URL: string = 'https://fixture.test/runtime-scope';
const RUNTIME_SCOPE_FIXTURE_SOURCE: LegadoBookSource = {
  bookSourceUrl: RUNTIME_SCOPE_SOURCE_URL,
  bookSourceName: 'runtime-scope-fixture',
  bookSourceType: 0
};
const FIXTURE_SOURCE: string = '{"bookSourceUrl":"http://127.0.0.1:18765","bookSourceName":"fixture-arkweb-success","bookSourceType":0,"enabledCookieJar":true,"searchUrl":"http://127.0.0.1:18765/web,{\\"webView\\":true,\\"webJs\\":\\"document.title\\",\\"webViewDelayTime\\":25}","ruleSearch":{"bookList":"body","bookUrl":"a","name":"a"}}';

/**
 * 独立 ArkWeb conformance 页面。它只访问本地确定性 fixture，
 * 用实际 Web 组件验证 WebView、webJs、Cookie 和 sourceRegex 的传输语义。
 */
@Entry
@Component
struct LegadoArkWebConformancePage {
  private executionStarted: boolean = false;
  private executionFinished: boolean = false;

  aboutToAppear(): void {
    setTimeout((): void => {
      void this.waitForArkWebReady(0);
    }, 0);
  }

  build() {
    Stack() {
      LegadoWebViewComponent()
    }
    .width(1)
    .height(1)
  }

  private async waitForArkWebReady(attempt: number): Promise<void> {
    if (this.executionStarted || this.executionFinished) {
      return;
    }
    if (!getWebViewExecutor().isWebViewReady() || !getLegadoRuntimeV2().isReady()) {
      if (attempt >= READY_RETRY_LIMIT) {
        this.finishFailure('ArkWeb controller did not become ready within 10 seconds.');
        return;
      }
      setTimeout((): void => {
        void this.waitForArkWebReady(attempt + 1);
      }, READY_RETRY_DELAY_MS);
      return;
    }

    this.executionStarted = true;
    await this.executeFixtures();
  }

  private async executeFixtures(): Promise<void> {
    try {
      const compiled = await new LegadoCompatibilityCompiler().compileOne(FIXTURE_SOURCE);
      if (compiled === null) {
        throw new Error('ArkWeb fixture source could not be compiled.');
      }

      await getCookieStore().removeCookie(FIXTURE_WEB_URL, 'arkweb_fixture');
      const planner = new LegadoRequestPlanner(compiled);
      const router = new LegadoTransportRouter();

      const webJsRequest = await planner.plan(
        LegadoWorkflowKind.SEARCH,
        compiled.source.searchUrl || ''
      );
      const webJsResponse = await router.execute(webJsRequest);
      this.assertArkWebResponse(webJsResponse, 'fixture-web-title', WEB_JS_SUMMARY, FIXTURE_WEB_URL);
      if (!webJsResponse.cookiesChanged) {
        throw new Error('ArkWeb fixture did not persist the fixture cookie into the compatibility cookie store.');
      }
      const storedCookie: string = getCookieStore().getCookie(FIXTURE_WEB_URL);
      if (storedCookie.indexOf('arkweb_fixture=arkweb-cookie') < 0) {
        throw new Error('ArkWeb fixture cookie value was not retained in the compatibility cookie store.');
      }
      this.emitTrace(webJsRequest, webJsResponse, WEB_JS_SUMMARY);

      const sourceRegexRequest = await planner.plan(
        LegadoWorkflowKind.SEARCH,
        FIXTURE_WEB_URL,
        '',
        1,
        FIXTURE_SOURCE_REGEX
      );
      const sourceRegexResponse = await router.execute(sourceRegexRequest);
      this.assertArkWebResponse(sourceRegexResponse, '/asset/found.css', SOURCE_REGEX_SUMMARY, FIXTURE_WEB_URL);
      this.emitTrace(sourceRegexRequest, sourceRegexResponse, SOURCE_REGEX_SUMMARY);

      const cookieRoundtripRequest = await planner.plan(
        LegadoWorkflowKind.SEARCH,
        `${FIXTURE_COOKIE_ECHO_URL},{"webView":true,"webJs":"document.title"}`
      );
      const cookieRoundtripResponse = await router.execute(cookieRoundtripRequest);
      this.assertArkWebResponse(
        cookieRoundtripResponse,
        'fixture-web-cookie-echo-true',
        COOKIE_ROUNDTRIP_SUMMARY,
        FIXTURE_COOKIE_ECHO_URL
      );
      this.emitTrace(cookieRoundtripRequest, cookieRoundtripResponse, COOKIE_ROUNDTRIP_SUMMARY);

      await this.assertRuntimeScopeReplayIsolation();
      await this.assertRuntimeWorkflowBindingContract();
      await this.assertRuntimeJavaApiContract();
      await this.assertRuntimeHighFrequencyApiContract();
      await this.assertRuntimeContextApiContract();
      await this.assertRuntimeNestedWebViewContract();
      await this.assertRuntimeSymmetricCryptoContract();
      await this.assertRuntimeJavaImporterCipherContract();
      await this.assertRuntimeHmacContract();
      await this.assertRuntimePostfixJsContract();
      await this.assertRuntimeJsonPrefixJsContract();
      await this.assertRuntimeTopLevelJsBooleanContract();
      await this.assertRuntimeDynamicEvalProbe();
      await this.assertRuntimeTocJsObjectProjection();
      await this.assertBookInfoInitContentTransition();

      this.finishSuccess();
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.finishFailure(message);
    }
  }

  private assertArkWebResponse(
    response: ResponseEnvelope,
    expectedBody: string,
    summary: string,
    expectedFinalUrl: string
  ): void {
    if (response.transport !== LegadoTransportKind.ARK_WEB) {
      throw new Error(`${summary}: transport was not ark_web.`);
    }
    if (response.errorCode !== LegadoExecutionErrorCode.NONE) {
      throw new Error(`${summary}: ArkWeb transport failed: ${response.errorMessage}`);
    }
    if (response.finalUrlObservation !== LegadoFinalUrlObservation.OBSERVED) {
      throw new Error(`${summary}: ArkWeb did not report an observed final URL.`);
    }
    if (response.finalUrl !== expectedFinalUrl) {
      throw new Error(`${summary}: ArkWeb final URL did not match the fixture target.`);
    }
    if (response.body.indexOf(expectedBody) < 0) {
      throw new Error(`${summary}: expected fixture result was not observed.`);
    }
  }

  private emitTrace(request: RequestSpec, response: ResponseEnvelope, summary: string): void {
    const trace = new LegadoExecutionTrace(
      request.traceId,
      request.sourceUrl,
      request.workflow,
      request,
      response,
      [],
      summary
    );
    hilog.info(
      LOG_DOMAIN,
      TAG,
      'MANXIA_LEGADO_TRACE:%{public}s',
      LegadoTraceSerializer.toRedactedJson(trace)
    );
    hilog.info(
      LOG_DOMAIN,
      TAG,
      'MANXIA_LEGADO_TRACE_STATUS:%{public}s',
      `${summary}|${response.transport}|${response.errorCode}|${response.cookiesChanged}`
    );
  }

  /**
   * A crypto call forces RuntimeV2 through its native bridge and a complete JS
   * replay. The replay and the next rule must both receive fresh bindings,
   * matching Legado's Rhino bindings-with-shared-prototype contract.
   */
  private async assertRuntimeScopeReplayIsolation(): Promise<void> {
    const runtime = getLegadoRuntimeV2();
    const runtimeContext: JsContext = {
      source: RUNTIME_SCOPE_FIXTURE_SOURCE
    };
    const first = await runtime.execute(
      "runtimeFixtureLeak = 'must-not-survive'; java.md5Encode('abc')",
      runtimeContext
    );
    if (!first.success || first.result !== '900150983cd24fb0d6963f7d28e17f72') {
      throw new Error(
        `${RUNTIME_SCOPE_REPLAY_SUMMARY}: digest bridge replay did not complete; ` +
        `success=${first.success};result=${first.result};error=${first.error || 'none'}`
      );
    }

    const second = await runtime.execute('typeof runtimeFixtureLeak', runtimeContext);
    if (!second.success || second.result !== 'undefined') {
      throw new Error(`${RUNTIME_SCOPE_REPLAY_SUMMARY}: rule-local state leaked across executions.`);
    }

    const repeated = await runtime.execute("java.md5Encode('abc')", runtimeContext);
    if (!repeated.success || repeated.result !== first.result) {
      throw new Error(`${RUNTIME_SCOPE_REPLAY_SUMMARY}: replay result was not deterministic.`);
    }

    hilog.info(
      LOG_DOMAIN,
      TAG,
      'MANXIA_LEGADO_TRACE_STATUS:%{public}s',
      `${RUNTIME_SCOPE_REPLAY_SUMMARY}|passed|${first.result}`
    );
  }

  /**
   * AnalyzeRule and AnalyzeUrl expose workflow objects for every JS rule, even
   * when a chained selector replaces `result`. This fixture guards that
   * analyzer-generated contexts keep source/book/chapter/key/page/variables.
   */
  private async assertRuntimeWorkflowBindingContract(): Promise<void> {
    const book = SafeUtils.parseObj('{}') as Record<string, string>;
    book.bookUrl = 'https://fixture.test/book';
    book.name = 'fixture-book';
    book.type = '0';
    const chapter = SafeUtils.parseObj('{}') as Record<string, string>;
    chapter.url = 'https://fixture.test/chapter';
    chapter.title = 'fixture-chapter';
    chapter.index = '7';
    const analyzer = new LegadoRuleAnalyzer();
    analyzer.setJsLib('');
    analyzer.setContent('fixture-body', RUNTIME_SCOPE_SOURCE_URL);
    analyzer.setJsExecutionBinding(
      new LegadoRuleJsExecutionBinding(
        RUNTIME_SCOPE_FIXTURE_SOURCE,
        book,
        chapter,
        'fixture-key',
        3
      )
    );
    analyzer.put('fixtureVariable', 'fixture-variable');
    const result = await analyzer.getStringAsync(
      '<js>[source.bookSourceName,book.bookUrl,chapter.title,key,page,java.get("fixtureVariable")].join("|")</js>'
    );
    const expected = 'runtime-scope-fixture|https://fixture.test/book|fixture-chapter|fixture-key|3|fixture-variable';
    if (result !== expected) {
      throw new Error(`${RUNTIME_WORKFLOW_BINDING_SUMMARY}: binding output did not match expected contract.`);
    }
    hilog.info(
      LOG_DOMAIN,
      TAG,
      'MANXIA_LEGADO_TRACE_STATUS:%{public}s',
      `${RUNTIME_WORKFLOW_BINDING_SUMMARY}|passed|source-book-chapter-key-page-variable`
    );
  }

  /**
   * Validates the Java bridge only inside the real ArkWeb runtime.  A test
   * ability has no Web component and must instead assert WEBVIEW_NOT_READY.
   */
  private async assertRuntimeJavaApiContract(): Promise<void> {
    const variables: Record<string, string> = {};
    variables.headers = 'fixture-header';
    const context: JsContext = { variables: variables, source: RUNTIME_SCOPE_FIXTURE_SOURCE };
    const runtime = getLegadoRuntimeV2();
    const values = await runtime.execute(
      "JSON.stringify([java.get('headers'), java.encodeURI('a b~'), java.md5Encode('abc'), java.md5Encode('你好'), java.timeFormat(0), java.timeFormatUTC(0, 'yyyy-MM-dd HH:mm', 0)])",
      context
    );
    const expectedPrefix = '["fixture-header","a+b%7E","900150983cd24fb0d6963f7d28e17f72","7eca689f0d3389d9dea66ae112e5cfd7",';
    const timeFormatPattern = /^\["fixture-header","a\+b%7E","900150983cd24fb0d6963f7d28e17f72","7eca689f0d3389d9dea66ae112e5cfd7","\d{4}\/\d{2}\/\d{2} \d{2}:\d{2}","1970-01-01 00:00"\]$/;
    if (!values.success || !values.result.startsWith(expectedPrefix) || !timeFormatPattern.test(values.result)) {
      throw new Error(
        `${RUNTIME_JAVA_API_SUMMARY}: get/encodeURI/md5 contract failed; ` +
        `success=${values.success};resultLength=${values.result.length};error=${values.error || 'none'}`
      );
    }
    const primitives = await runtime.execute(
      "JSON.stringify([java.md5Encode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'), Object.keys({z:'3',a:'1',m:'2'}).sort().join(',')])",
      context
    );
    if (!primitives.success || primitives.result !== '["b15af9cdabbaea0516866a33d8fd0f98","a,m,z"]') {
      throw new Error(
        `${RUNTIME_JAVA_API_SUMMARY}: deterministic JavaScript primitive contract failed; ` +
        `success=${primitives.success};resultLength=${primitives.result.length};error=${primitives.error || 'none'}`
      );
    }
    const emptyVariables: Record<string, string> = {};
    const missingContext: JsContext = { variables: emptyVariables };
    const missingVariable = await runtime.execute(
      "var headers = 'runtime-only'; java.get('headers')",
      missingContext
    );
    if (!missingVariable.success || missingVariable.result !== '') {
      throw new Error(
        `${RUNTIME_JAVA_API_SUMMARY}: java.get read an undeclared runtime local; ` +
        `success=${missingVariable.success};resultLength=${missingVariable.result.length};error=${missingVariable.error || 'none'}`
      );
    }
    const sourceFields = await runtime.execute(
      "JSON.stringify([source.bookSourceName.includes('runtime'), source.bookSourceType, source.bookSourceUrl])",
      context
    );
    const expectedSourceFields = '[true,0,"https://fixture.test/runtime-scope"]';
    if (!sourceFields.success || sourceFields.result !== expectedSourceFields) {
      throw new Error(
        `${RUNTIME_JAVA_API_SUMMARY}: injected source field contract failed; ` +
        `success=${sourceFields.success};result=${sourceFields.result};error=${sourceFields.error || 'none'}`
      );
    }
    const uuid = await runtime.execute(
      "var direct=java.randomUUID();var nested=java.util.UUID.randomUUID().toString();" +
      "JSON.stringify([/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(direct)," +
      "direct===direct.toString(),/^[0-9a-f-]{36}$/i.test(nested)])",
      context
    );
    if (!uuid.success || uuid.result !== '[true,true,true]') {
      throw new Error(
        `${RUNTIME_JAVA_API_SUMMARY}: randomUUID and UUID.toString contract failed; ` +
        `success=${uuid.success};result=${uuid.result};error=${uuid.error || 'none'}`
      );
    }
    const postResponse = await runtime.execute(
      "java.post('http://127.0.0.1:18765/header-post', 'q=fixture', {'X-Legado-Header':'fixture-header'}).body()",
      context
    );
    if (!postResponse.success || postResponse.result.indexOf('fixture-header-post') < 0) {
      throw new Error(
        `${RUNTIME_JAVA_API_SUMMARY}: java.post contract failed; ` +
        `success=${postResponse.success};result=${postResponse.result};error=${postResponse.error || 'none'}`
      );
    }
    hilog.info(
      LOG_DOMAIN,
      TAG,
      'MANXIA_LEGADO_TRACE_STATUS:%{public}s',
      `${RUNTIME_JAVA_API_SUMMARY}|passed|get-encodeURI-md5-source-fields-time-format-uuid`
    );
  }

  /**
   * JsEncodeUtils defines HMacHex(data, algorithm, key).  This must be
   * validated through the native bridge rather than through a JavaScript
   * placeholder: a deterministic but invalid signature is worse than an
   * explicit failure because remote book-source servers reject it silently.
   */
  private async assertRuntimeHmacContract(): Promise<void> {
    const runtime = getLegadoRuntimeV2();
    const context: JsContext = { source: RUNTIME_SCOPE_FIXTURE_SOURCE };
    const result = await runtime.execute(
      "JSON.stringify([java.HMacHex('The quick brown fox jumps over the lazy dog', 'HmacMD5', 'key'), " +
      "java.HMacHex('The quick brown fox jumps over the lazy dog', 'HmacSHA256', 'key')])",
      context
    );
    const expected =
      '["80070713463e7749b90c2dc24911e275","f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"]';
    if (!result.success || result.result !== expected) {
      throw new Error(
        `${RUNTIME_HMAC_SUMMARY}: standard-vector output diverged; ` +
        `success=${result.success};result=${result.result};error=${result.error || 'none'}`
      );
    }
    const invalid = await runtime.execute(
      "java.HMacHex('payload', 'HmacFixtureUnsupported', 'key')",
      context
    );
    if (invalid.success || (invalid.error || '').indexOf('CRYPTO_HMAC_FAILED') < 0) {
      throw new Error(
        `${RUNTIME_HMAC_SUMMARY}: unsupported algorithm was not surfaced as a structured bridge failure; ` +
        `success=${invalid.success};error=${invalid.error || 'none'}`
      );
    }
    hilog.info(
      LOG_DOMAIN,
      TAG,
      'MANXIA_LEGADO_TRACE_STATUS:%{public}s',
      `${RUNTIME_HMAC_SUMMARY}|passed|hmac-md5-sha256-structured-failure`
    );
  }

  private async assertRuntimeHighFrequencyApiContract(): Promise<void> {
    const runtime = getLegadoRuntimeV2();
    const context: JsContext = { source: RUNTIME_SCOPE_FIXTURE_SOURCE };
    const result = await runtime.execute(
      "JSON.stringify([java.t2s('繁體中文書源'), java.hexDecodeToString('E4BDA0E5A5BD'), java.getStringList('p', '<p>A</p><p>B</p>').join('|')])",
      context
    );
    if (!result.success || result.result !== '["繁体中文书源","你好","A|B"]') {
      throw new Error(
        `${RUNTIME_HIGH_FREQUENCY_API_SUMMARY}: t2s/hexDecodeToString/getStringList contract failed; ` +
        `success=${result.success};result=${result.result};error=${result.error || 'none'}`
      );
    }
    hilog.info(
      LOG_DOMAIN,
      TAG,
      'MANXIA_LEGADO_TRACE_STATUS:%{public}s',
      `${RUNTIME_HIGH_FREQUENCY_API_SUMMARY}|passed|t2s-hexDecodeToString-getStringList`
    );
  }

  private async assertRuntimeContextApiContract(): Promise<void> {
    const runtime = getLegadoRuntimeV2();
    const context: JsContext = { source: RUNTIME_SCOPE_FIXTURE_SOURCE, result: 'before' };
    const result = await runtime.execute(
      "JSON.stringify([java.setContent('after'), java.getContent ? java.getContent() : java.get('result'), java.getWebViewUA() !== ''])",
      context
    );
    if (!result.success || result.result !== '[\"after\",\"after\",true]') {
      throw new Error(
        `${RUNTIME_CONTEXT_API_SUMMARY}: setContent/getWebViewUA contract failed; ` +
        `success=${result.success};result=${result.result};error=${result.error || 'none'}`
      );
    }
    hilog.info(
      LOG_DOMAIN,
      TAG,
      'MANXIA_LEGADO_TRACE_STATUS:%{public}s',
      `${RUNTIME_CONTEXT_API_SUMMARY}|passed|setContent-getWebViewUA`
    );
  }

  private async assertRuntimeNestedWebViewContract(): Promise<void> {
    const runtime = getLegadoRuntimeV2();
    const context: JsContext = { source: RUNTIME_SCOPE_FIXTURE_SOURCE };
    const webView = await runtime.execute(
      "java.webView(null, 'http://127.0.0.1:18765/web', null)",
      context
    );
    const overrideUrl = await runtime.execute(
      "java.webViewGetOverrideUrl(null, 'http://127.0.0.1:18765/web', null, '')",
      context
    );
    const expectedError: string = 'ARKWEB_NESTED_WEBVIEW_UNSUPPORTED';
    if (webView.success || overrideUrl.success ||
      (webView.error || '').indexOf(expectedError) < 0 ||
      (overrideUrl.error || '').indexOf(expectedError) < 0) {
      throw new Error(
        `${RUNTIME_NESTED_WEBVIEW_SUMMARY}: nested WebView must fail explicitly; ` +
        `webView=${webView.success}/${webView.error || 'none'};` +
        `override=${overrideUrl.success}/${overrideUrl.error || 'none'}`
      );
    }
    hilog.info(
      LOG_DOMAIN,
      TAG,
      'MANXIA_LEGADO_TRACE_STATUS:%{public}s',
      `${RUNTIME_NESTED_WEBVIEW_SUMMARY}|passed|explicit-unsupported-no-empty-fallback`
    );
  }

  private async assertRuntimeSymmetricCryptoContract(): Promise<void> {
    const runtime = getLegadoRuntimeV2();
    const context: JsContext = { source: RUNTIME_SCOPE_FIXTURE_SOURCE };
    const result = await runtime.execute(
      "var ecbKey=java.hexDecodeToByteArray('000102030405060708090a0b0c0d0e0f');" +
      "var ecb=java.createSymmetricCrypto('AES/ECB/Pkcs7Padding',ecbKey,'');" +
      "var cbcKey=java.hexDecodeToByteArray('2b7e151628aed2a6abf7158809cf4f3c');" +
      "var cbcIv=java.hexDecodeToByteArray('000102030405060708090a0b0c0d0e0f');" +
      "var cbc=java.createSymmetricCrypto('AES/CBC/PKCS5Padding',cbcKey,cbcIv);" +
      "var legacy=java.createSymmetricCrypto('AES/ECB/PKCS5Padding','1234567890123456','');" +
      "var legacyCipher=legacy.encryptBase64('fixture-aes-text');" +
      "var desKey=java.hexDecodeToByteArray('0123456789abcdef');" +
      "var desIv=java.hexDecodeToByteArray('1234567890abcdef');" +
      "var desCbc=java.createSymmetricCrypto('DES/CBC/PKCS5Padding',desKey,desIv);" +
      "var desLegacy=java.desEncodeToBase64String('fixture-des','12345678','DES/ECB/PKCS5Padding','');" +
      "var tripleKey=java.hexDecodeToByteArray('0123456789abcdeffedcba98765432100011223344556677');" +
      "var triple=java.createSymmetricCrypto('DESede/ECB/PKCS5Padding',tripleKey,'');" +
      // Legado's Hutool symmetric object exposes decryptStr for textual data;
      // the source package uses decryptStr, not the non-contract decryptHex alias.
      "JSON.stringify([ecb.encryptHex('fixture-ecb'),ecb.decryptStr('92d1ab4667ace70742bde5e41506cf77')," +
      "cbc.encryptHex('fixture-cbc'),cbc.decryptStr('c0f9f0a5a50d0230f87d60b32e5ddc0c')," +
      "legacy.decryptStr(legacyCipher),java.aesBase64DecodeToString(legacyCipher,'1234567890123456','AES/ECB/PKCS5Padding','')," +
      "desCbc.encryptHex('fixture-des'),desCbc.decryptStr('592970d5f1f3185360359759e441e55d'),desLegacy," +
      "triple.encryptHex('fixture-3des'),triple.decryptStr('fab272359da293ce271bf0e52163b23a')])",
      context
    );
    const expected = '["92d1ab4667ace70742bde5e41506cf77","fixture-ecb",' +
      '"c0f9f0a5a50d0230f87d60b32e5ddc0c","fixture-cbc",' +
      '"fixture-aes-text","fixture-aes-text",' +
      '"592970d5f1f3185360359759e441e55d","fixture-des","CLw7JVk/kAzTcJ+fk8AsQA==",' +
      '"fab272359da293ce271bf0e52163b23a","fixture-3des"]';
    if (!result.success || result.result !== expected) {
      throw new Error(
        `${RUNTIME_SYMMETRIC_CRYPTO_SUMMARY}: AES vector or legacy wrapper contract failed; ` +
        `success=${result.success};result=${result.result};error=${result.error || 'none'}`
      );
    }
    hilog.info(
      LOG_DOMAIN,
      TAG,
      'MANXIA_LEGADO_TRACE_STATUS:%{public}s',
      `${RUNTIME_SYMMETRIC_CRYPTO_SUMMARY}|passed|aes-des-3des-legacy-wrapper`
    );
  }

  /**
   * Real book sources commonly use Rhino's JavaImporter syntax instead of
   * Legado's newer java.createSymmetricCrypto helper.  This verifies that the
   * bounded Java package adapter performs actual AES/CBC decryption rather
   * than merely admitting the package names during compilation.
   */
  private async assertRuntimeJavaImporterCipherContract(): Promise<void> {
    const runtime = getLegadoRuntimeV2();
    const context: JsContext = { source: RUNTIME_SCOPE_FIXTURE_SOURCE };
    const result = await runtime.execute(
      "var ji=new JavaImporter();" +
      "ji.importPackage(Packages.java.lang,Packages.javax.crypto.spec,Packages.javax.crypto,Packages.java.util);" +
      "with(ji){var packed=Base64.getDecoder().decode('AAECAwQFBgcICQoLDA0OD0gQnIdHIudkXXcM8e8qBs8=');" +
      "var key=new SecretKeySpec(String('1234567890123456').getBytes(),'AES');" +
      "var iv=new IvParameterSpec(Arrays.copyOfRange(packed,0,16));" +
      "var cipher=Cipher.getInstance('AES/CBC/PKCS5Padding');cipher.init(2,key,iv);" +
      "String(cipher.doFinal(Arrays.copyOfRange(packed,16,packed.length)));}",
      context
    );
    if (!result.success || result.result !== 'fixture-cbc') {
      throw new Error(
        `${RUNTIME_JAVA_IMPORTER_CIPHER_SUMMARY}: JavaImporter AES/CBC decrypt failed; ` +
        `success=${result.success};result=${result.result};error=${result.error || 'none'}`
      );
    }
    hilog.info(
      LOG_DOMAIN,
      TAG,
      'MANXIA_LEGADO_TRACE_STATUS:%{public}s',
      `${RUNTIME_JAVA_IMPORTER_CIPHER_SUMMARY}|passed|aes-cbc-pkcs5`
    );
  }

  /**
   * Keeps postfix-JS parsing and its Search workflow execution in the same
   * live ArkWeb host that the production V2 path uses.
   */
  private async assertRuntimePostfixJsContract(): Promise<void> {
    const analyzer = new LegadoRuleAnalyzer();
    analyzer.setContent('{"sourceId":"fixture-source-id"}', RUNTIME_SCOPE_SOURCE_URL);
    const postfixValue = await analyzer.getStringAsync('sourceId@js:result + "-detail"');
    if (postfixValue !== 'fixture-source-id-detail') {
      throw new Error(`${RUNTIME_POSTFIX_JS_SUMMARY}: JSON postfix rule did not receive the item result.`);
    }

    const urlAnalyzer = new LegadoUrlAnalyzer('https://fixture.test/book', RUNTIME_SCOPE_SOURCE_URL);
    urlAnalyzer.setVariable('result', 'stale-result');
    const parsed = await urlAnalyzer.analyzeUrlAsync('@js:result');
    if (parsed.url !== 'https://fixture.test/@js:result') {
      throw new Error(`${RUNTIME_POSTFIX_JS_SUMMARY}: top-level @js result scope diverged from AnalyzeUrl.`);
    }

    const raw = '{"bookSourceUrl":"http://127.0.0.1:18765","bookSourceName":"fixture-postfix-js-book-url","bookSourceType":0,"searchUrl":"http://127.0.0.1:18765/search","ruleSearch":{"bookList":"$.items","bookUrl":"$.url@js:\\nresult","name":"$.name"}}';
    const compiled = await new LegadoCompatibilityCompiler().compileOne(raw);
    if (compiled === null) {
      throw new Error(`${RUNTIME_POSTFIX_JS_SUMMARY}: postfix source did not compile.`);
    }
    const workflow = new LegadoWorkflowOrchestrator(compiled);
    const search = await workflow.search('fixture');
    if (search.books.length !== 1 || search.books[0].bookUrl !== 'http://127.0.0.1:18765/book/1') {
      throw new Error(`${RUNTIME_POSTFIX_JS_SUMMARY}: multiline postfix book URL did not reach the Search output.`);
    }
    const trace = workflow.getLastTrace();
    if (trace === null || !trace.outputSummary.includes('bookUrlJsResult=1')) {
      throw new Error(`${RUNTIME_POSTFIX_JS_SUMMARY}: Search trace did not record postfix JS evaluation.`);
    }
    hilog.info(
      LOG_DOMAIN,
      TAG,
      'MANXIA_LEGADO_TRACE_STATUS:%{public}s',
      `${RUNTIME_POSTFIX_JS_SUMMARY}|passed|json-postfix-top-level-search`
    );
  }

  /**
   * JSON book-source rules may attach `<js>` directly to a JSONPath. The
   * analyzer must evaluate the path first, expose that value as `result`,
   * and retain Java bridge side effects from the trailing script.
   */
  private async assertRuntimeJsonPrefixJsContract(): Promise<void> {
    const analyzer = new LegadoRuleAnalyzer();
    analyzer.setContent('{"bid":"fixture-book-id"}', RUNTIME_SCOPE_SOURCE_URL);
    const value = await analyzer.getStringAsync(
      "$.bid<js>java.put('prefixFixture', result + '-stored'); result + '-detail'</js>"
    );
    if (value !== 'fixture-book-id-detail' ||
      analyzer.getVariableValue('prefixFixture') !== 'fixture-book-id-stored' ||
      analyzer.getLastJsExecutionStatus() !== 'result') {
      throw new Error(
        `${RUNTIME_JSON_PREFIX_JS_SUMMARY}: JSON prefix JS did not preserve result or java.put side effect; ` +
        `status=${analyzer.getLastJsExecutionStatus()};valueLength=${value.length}`
      );
    }
    hilog.info(
      LOG_DOMAIN,
      TAG,
      'MANXIA_LEGADO_TRACE_STATUS:%{public}s',
      `${RUNTIME_JSON_PREFIX_JS_SUMMARY}|passed|json-prefix-result-and-put`
    );
  }

  /**
   * A complete top-level JS rule owns boolean operators in its program.  They
   * are not Legado's rule-combinator tokens.  This is intentionally executed
   * in the live ArkWeb host because the production path also relies on its JS
   * bridge rather than the headless instrumentation process.
   */
  private async assertRuntimeTopLevelJsBooleanContract(): Promise<void> {
    const analyzer = new LegadoRuleAnalyzer();
    analyzer.setContent('{"id":123}', RUNTIME_SCOPE_SOURCE_URL);
    const bookUrl = await analyzer.getUrlStringAsync(
      '@js:\n' +
      'var id={{$.id}};\n' +
      'id === 123 || id === 0 ? \'/book/123,{"headers":{"X-Legado-Carrier":"fixture-carrier"}}\' : \'\''
    );
    if (bookUrl.indexOf('/book/123,{"headers"') < 0 || analyzer.getLastJsExecutionStatus() !== 'result') {
      throw new Error(
        `${RUNTIME_TOP_LEVEL_JS_BOOLEAN_SUMMARY}: top-level JS boolean expression was not evaluated as one program; ` +
        `status=${analyzer.getLastJsExecutionStatus()};resultLength=${bookUrl.length}`
      );
    }
    hilog.info(
      LOG_DOMAIN,
      TAG,
      'MANXIA_LEGADO_TRACE_STATUS:%{public}s',
      `${RUNTIME_TOP_LEVEL_JS_BOOLEAN_SUMMARY}|passed|template-boolean-url-option`
    );
  }

  /**
   * Separates direct eval, source-scoped binding and dynamic
   * source.bookSourceComment evaluation on the real ArkWeb runtime.  The
   * probe is intentionally side-effect free and only emits result lengths and
   * the redacted runtime diagnostic on failure.
   */
  private async assertRuntimeDynamicEvalProbe(): Promise<void> {
    const runtime = getLegadoRuntimeV2();
    const source: LegadoBookSource = {
      bookSourceUrl: RUNTIME_SCOPE_SOURCE_URL,
      bookSourceName: 'dynamic-eval-probe-source',
      bookSourceType: 0,
      bookSourceComment: 'String("dynamic-source-comment-ok")'
    };
    const context: JsContext = { source };
    const probes: Array<[string, string, string]> = [
      ['direct', "eval('1 + 1')", '2'],
      ['source_binding', "eval('String(source.bookSourceName)')", 'dynamic-eval-probe-source'],
      ['source_comment', 'eval(String(source.bookSourceComment))', 'dynamic-source-comment-ok']
    ];
    for (let i = 0; i < probes.length; i++) {
      const probe: [string, string, string] = probes[i];
      const result: JsExecuteResult = await runtime.execute(probe[1], context);
      this.emitRuntimeEvalProbe(probe[0], result);
      if (!result.success || result.result !== probe[2]) {
        const diagnostic: string = result.diagnostic || 'none';
        throw new Error(
          `${RUNTIME_DYNAMIC_EVAL_PROBE_SUMMARY}: ${probe[0]} failed;` +
          `success=${result.success};resultLength=${result.result.length};diagnostic=${diagnostic}`
        );
      }
    }
    const functionSource: LegadoBookSource = {
      bookSourceUrl: RUNTIME_SCOPE_SOURCE_URL,
      bookSourceName: 'dynamic-eval-function-source',
      bookSourceType: 0,
      bookSourceComment: 'function getChapterList(){return "source-comment-function-ok"}'
    };
    const functionResult: JsExecuteResult = await runtime.execute(
      'eval(String(source.bookSourceComment)); getChapterList()',
      { source: functionSource }
    );
    this.emitRuntimeEvalProbe('source_comment_function', functionResult);
    if (!functionResult.success || functionResult.result !== 'source-comment-function-ok') {
      const diagnostic: string = functionResult.diagnostic || 'none';
      throw new Error(
        `${RUNTIME_DYNAMIC_EVAL_PROBE_SUMMARY}: source_comment_function failed;` +
        `success=${functionResult.success};resultLength=${functionResult.result.length};diagnostic=${diagnostic}`
      );
    }
    hilog.info(
      LOG_DOMAIN,
      TAG,
      'MANXIA_LEGADO_TRACE_STATUS:%{public}s',
      `${RUNTIME_DYNAMIC_EVAL_PROBE_SUMMARY}|passed|direct-source-binding-source-comment`
    );
  }

  private emitRuntimeEvalProbe(label: string, result: JsExecuteResult): void {
    const state: string = result.success ? 'passed' : 'failed';
    const diagnostic: string = result.diagnostic || 'none';
    hilog.info(
      LOG_DOMAIN,
      TAG,
      'MANXIA_LEGADO_TRACE_STATUS:%{public}s',
      `${RUNTIME_DYNAMIC_EVAL_PROBE_SUMMARY}|${label}|${state}|resultLength=${result.result.length}|diagnostic=${diagnostic}`
    );
  }

  /**
   * Exercises the IMAGE-source pattern that builds `{cn, cu, ci}` objects in
   * source.bookSourceComment, then projects each object through the normal
   * Legado JSON rule chain. This stays local and deterministic while using the
   * same ArkWeb JS bridge as production workflows.
   */
  private async assertRuntimeTocJsObjectProjection(): Promise<void> {
    const source: LegadoBookSource = {
      bookSourceUrl: RUNTIME_SCOPE_SOURCE_URL,
      bookSourceName: 'runtime-toc-js-object-source',
      bookSourceType: 2,
      bookSourceComment: 'function getChapterList(cn,cu,ci){var names=java.getStringList(cn);var urls=java.getStringList(cu);var infos=ci===""?[]:java.getStringList(ci);var list=[];for(var i=0;i<names.length;i++){list.push({cn:names[i],cu:urls[i],ci:infos[i]||""});}return list;}'
    };
    const filler: string = 'fixture-padding-'.repeat(5000);
    const html: string = '<section class="fixture-list"><article><a href="/chapter/one">One</a></article>' +
      '<article><a href="/chapter/two">Two</a></article></section>' + filler;
    const tocJsCode: string = 'eval(String(source.bookSourceComment));\n' +
      'var lis=getChapterList("class.fixture-list@tag.article@tag.a@text",' +
      '"class.fixture-list@tag.article@tag.a@href","");\n' +
      'lis';
    const runtime = getLegadoRuntimeV2();
    const directRuntimeResult: JsExecuteResult = await runtime.execute(tocJsCode, {
      source,
      result: html,
      src: html,
      baseUrl: RUNTIME_SCOPE_SOURCE_URL
    });
    if (!directRuntimeResult.success) {
      throw new Error(
        `${RUNTIME_TOC_JS_OBJECT_SUMMARY}: direct runtime failed;` +
        `diagnostic=${directRuntimeResult.diagnostic || 'none'}`
      );
    }
    const directRuntimeText: string = directRuntimeResult.result;
    if (directRuntimeText.indexOf('"cn"') < 0 || directRuntimeText.indexOf('"cu"') < 0) {
      throw new Error(
        `${RUNTIME_TOC_JS_OBJECT_SUMMARY}: direct runtime returned unexpected shape;` +
        `resultLength=${directRuntimeText.length}`
      );
    }
    hilog.info(
      LOG_DOMAIN,
      TAG,
      'MANXIA_LEGADO_TRACE_STATUS:%{public}s',
      `${RUNTIME_TOC_JS_OBJECT_SUMMARY}|direct-runtime|passed|resultLength=${directRuntimeText.length}`
    );
    const analyzer = new LegadoRuleAnalyzer();
    analyzer.setContent(html, RUNTIME_SCOPE_SOURCE_URL);
    analyzer.setJsExecutionBinding(new LegadoRuleJsExecutionBinding(source, undefined, undefined, '', 1));
    const analyzerWithoutJsonSuffix: string = `<js>${tocJsCode}</js>`;
    const parsedAnalyzerRule = analyzer.parseRule(analyzerWithoutJsonSuffix);
    hilog.info(
      LOG_DOMAIN,
      TAG,
      'MANXIA_LEGADO_TRACE_STATUS:%{public}s',
      `${RUNTIME_TOC_JS_OBJECT_SUMMARY}|analyzer-parse|mode=${String(parsedAnalyzerRule.mode)};ruleLength=${parsedAnalyzerRule.rule.length}`
    );
    const analyzerWithoutJsonElements: string[] = await analyzer.getElementsAsync(analyzerWithoutJsonSuffix);
    if (analyzerWithoutJsonElements.length !== 2) {
      const analyzerStatusBeforeFallback: string = analyzer.getLastJsExecutionStatus();
      const analyzerFallbackResult: string = await analyzer.evalJSAsync(tocJsCode);
      hilog.info(
        LOG_DOMAIN,
        TAG,
        'MANXIA_LEGADO_TRACE_STATUS:%{public}s',
        `${RUNTIME_TOC_JS_OBJECT_SUMMARY}|analyzer-eval-fallback|before=${analyzerStatusBeforeFallback};after=${analyzer.getLastJsExecutionStatus()};length=${analyzerFallbackResult.length};jsonArray=${analyzerFallbackResult.trim().startsWith('[')}`
      );
      throw new Error(
        `${RUNTIME_TOC_JS_OBJECT_SUMMARY}: analyzer without JSON suffix failed;` +
        `elements=${analyzerWithoutJsonElements.length};jsStatus=${analyzerStatusBeforeFallback}`
      );
    }
    hilog.info(
      LOG_DOMAIN,
      TAG,
      'MANXIA_LEGADO_TRACE_STATUS:%{public}s',
      `${RUNTIME_TOC_JS_OBJECT_SUMMARY}|analyzer-no-json|passed|elements=${analyzerWithoutJsonElements.length}`
    );
    const rule: string = `${analyzerWithoutJsonSuffix}$.[*]`;
    const elements: string[] = await analyzer.getElementsAsync(rule);
    if (elements.length !== 2) {
      throw new Error(`${RUNTIME_TOC_JS_OBJECT_SUMMARY}: projected element count=${elements.length};jsStatus=${analyzer.getLastJsExecutionStatus()}`);
    }
    const first = new LegadoRuleAnalyzer();
    first.setContent(elements[0], RUNTIME_SCOPE_SOURCE_URL);
    const firstName: string = await first.getStringAsync('cn');
    const firstUrl: string = await first.getUrlStringAsync('cu');
    const firstInfo: string = await first.getStringAsync('ci');
    if (firstName !== 'One' || firstUrl !== '/chapter/one' || firstInfo !== '') {
      throw new Error(
        `${RUNTIME_TOC_JS_OBJECT_SUMMARY}: projected fields did not survive;` +
        `namePresent=${firstName.length > 0};urlPresent=${firstUrl.length > 0};infoPresent=${firstInfo.length > 0}`
      );
    }
    hilog.info(
      LOG_DOMAIN,
      TAG,
      'MANXIA_LEGADO_TRACE_STATUS:%{public}s',
      `${RUNTIME_TOC_JS_OBJECT_SUMMARY}|passed|elements=${elements.length};namePresent=true;urlPresent=true;infoPresent=false`
    );
  }

  /** Mirrors BookInfo.analyzeBookInfo: init selects a new rule document. */
  private async assertBookInfoInitContentTransition(): Promise<void> {
    const analyzer = new LegadoRuleAnalyzer();
    analyzer.setContent('{"id":"outer-id","payload":{"id":"inner-id"}}', RUNTIME_SCOPE_SOURCE_URL);
    const initializedElements = await analyzer.getElementsAsync('$.payload');
    if (initializedElements.length !== 1) {
      throw new Error(`${BOOK_INFO_INIT_TRANSITION_SUMMARY}: init did not select exactly one document.`);
    }
    analyzer.setContent(initializedElements[0], RUNTIME_SCOPE_SOURCE_URL);
    const resolvedId = await analyzer.getStringAsync('$.id');
    if (resolvedId !== 'inner-id') {
      throw new Error(`${BOOK_INFO_INIT_TRANSITION_SUMMARY}: later rule did not observe init content.`);
    }
    hilog.info(
      LOG_DOMAIN,
      TAG,
      'MANXIA_LEGADO_TRACE_STATUS:%{public}s',
      `${BOOK_INFO_INIT_TRANSITION_SUMMARY}|passed|inner-document-visible`
    );
  }

  private finishSuccess(): void {
    logger.info(TAG, 'ArkWeb fixture completed successfully.');
    this.executionFinished = true;
    this.terminateAfterTrace();
  }

  private finishFailure(message: string): void {
    logger.error(TAG, `ArkWeb fixture failed: ${message}`);
    hilog.error(LOG_DOMAIN, TAG, 'MANXIA_LEGADO_ARKWEB_FIXTURE_FAILED:%{public}s', message);
    this.executionFinished = true;
    this.terminateAfterTrace();
  }

  private terminateAfterTrace(): void {
    setTimeout((): void => {
      try {
        const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
        if (hostContext) {
          hostContext.terminateSelf();
        }
      } catch (error) {
        logger.warn(TAG, `Unable to terminate ArkWeb fixture ability: ${String(error)}`);
      }
    }, TERMINATE_DELAY_MS);
  }
}
