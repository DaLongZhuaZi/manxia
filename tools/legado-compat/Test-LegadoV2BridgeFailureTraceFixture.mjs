import fs from 'node:fs';
import vm from 'node:vm';

const runtimeHtml = fs.readFileSync('entry/src/main/resources/rawfile/legado_runtime.html', 'utf8');
const scriptMatch = runtimeHtml.match(/<script>\s*([\s\S]*?)<\/script>/i);
if (!scriptMatch) throw new Error('legado runtime script is missing');

const runtimeContext = {
  window: {}, console, Date, Math, JSON, Object, Array, String, Number, RegExp,
  Error, parseInt, parseFloat, isNaN, encodeURIComponent, decodeURIComponent,
  escape, unescape, Uint8Array, ArrayBuffer
};
runtimeContext.window = runtimeContext;
vm.createContext(runtimeContext);
runtimeContext.Function = vm.runInContext('Function', runtimeContext);
vm.runInContext(scriptMatch[1], runtimeContext);

function createPayload(code) {
  return {
    code,
    context: {
      baseUrl: 'http://fixture.test',
      sourceUrl: 'http://fixture.test',
      variables: { sourceUrl: 'http://fixture.test' },
      source: {
        bookSourceUrl: 'http://fixture.test',
        bookSourceName: 'bridge-failure-fixture',
        bookSourceType: '0'
      }
    },
    state: {
      bridgeResponses: {},
      variables: { sourceUrl: 'http://fixture.test' },
      cache: {},
      sourceData: {},
      randomSeed: 1,
      now: 1700000000000
    }
  };
}

const failedPayload = createPayload("JSON.parse(java.ajax('http://fixture.test/unreachable'))");
const first = JSON.parse(runtimeContext.__manxiaLegadoRuntimeExecute(failedPayload));
if (first.status !== 'pending' || first.bridgeRequests.length !== 1 || first.bridgeRequests[0].type !== 'http') {
  throw new Error(`expected one pending HTTP bridge request, got ${JSON.stringify(first)}`);
}
const failedRequest = first.bridgeRequests[0];
failedPayload.state.bridgeResponses[failedRequest.id] = {
  id: failedRequest.id,
  type: 'http',
  success: false,
  body: '',
  url: failedRequest.url,
  code: 0,
  headers: '',
  error: 'HTTP_FAILED: socket closed'
};
const failedReplay = JSON.parse(runtimeContext.__manxiaLegadoRuntimeExecute(failedPayload));
if (failedReplay.status !== 'error' || failedReplay.errorCode !== 'SCRIPT_SYNTAX') {
  throw new Error(`expected JS parse error after failed bridge replay, got ${JSON.stringify(failedReplay)}`);
}

const statusPayload = createPayload("java.ajax('http://fixture.test/status')");
const statusFirst = JSON.parse(runtimeContext.__manxiaLegadoRuntimeExecute(statusPayload));
const statusRequest = statusFirst.bridgeRequests[0];
statusPayload.state.bridgeResponses[statusRequest.id] = {
  id: statusRequest.id,
  type: 'http',
  success: true,
  body: '{"error":"denied"}',
  url: statusRequest.url,
  code: 401,
  headers: 'content-type: application/json'
};
const statusReplay = JSON.parse(runtimeContext.__manxiaLegadoRuntimeExecute(statusPayload));
if (statusReplay.status !== 'ok' || statusReplay.result !== '{"error":"denied"}') {
  throw new Error(`expected received HTTP error body to remain rule-readable, got ${JSON.stringify(statusReplay)}`);
}

console.log(JSON.stringify({
  status: 'passed',
  contract: 'nested_bridge_failure_and_http_status_body',
  rawScriptErrorCode: failedReplay.errorCode,
  failedBridgeCode: 0,
  receivedHttpStatus: 401
}));
