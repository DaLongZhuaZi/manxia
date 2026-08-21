import fs from 'node:fs';
import vm from 'node:vm';

const runtimeHtml = fs.readFileSync('entry/src/main/resources/rawfile/legado_runtime.html', 'utf8');
const scriptMatch = runtimeHtml.match(/<script>\s*([\s\S]*?)<\/script>/i);
if (!scriptMatch) {
  throw new Error('legado runtime script is missing');
}

const runtimeContext = {
  window: {},
  console,
  Date,
  Math,
  JSON,
  Object,
  Array,
  String,
  Number,
  RegExp,
  Error,
  parseInt,
  parseFloat,
  isNaN,
  encodeURIComponent,
  decodeURIComponent,
  escape,
  unescape,
  Uint8Array,
  ArrayBuffer
};
runtimeContext.window = runtimeContext;
vm.createContext(runtimeContext);
runtimeContext.Function = vm.runInContext('Function', runtimeContext);
vm.runInContext(scriptMatch[1], runtimeContext);

const source = {
  bookSourceUrl: 'http://fixture.test',
  bookSourceName: 'header-fixture',
  bookSourceType: '0',
  header: "@js:(()=>{ time = Date.now().toString(); token = get_token(time); return JSON.stringify({'X-Source-Auth':token,'X-Static':'source'}); })()",
  enabledCookieJar: false
};
const payload = {
  code: "java.ajax('http://fixture.test/data,{\"headers\":{\"X-Source-Auth\":\"override\"}}')",
  context: {
    baseUrl: 'http://fixture.test',
    sourceUrl: 'http://fixture.test',
    variables: { sourceUrl: 'http://fixture.test' },
    jsLib: 'function get_token(times){ const {java} = this; return java.HMacHex(String(times), "HmacSHA1", "fixture-key"); }',
    source
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

const first = JSON.parse(runtimeContext.__manxiaLegadoRuntimeExecute(payload));
if (first.status !== 'pending' || first.bridgeRequests[0].type !== 'crypto-hmac') {
  throw new Error(`expected pending crypto bridge, got ${JSON.stringify(first)}`);
}
const cryptoRequest = first.bridgeRequests[0];
payload.state.bridgeResponses[cryptoRequest.id] = {
  id: cryptoRequest.id,
  type: 'crypto-hmac',
  success: true,
  body: 'signed',
  url: '',
  code: 200,
  headers: ''
};
const second = JSON.parse(runtimeContext.__manxiaLegadoRuntimeExecute(payload));
const request = second.bridgeRequests.find((item) => item.type === 'http');
if (!request) {
  throw new Error('java.ajax did not create an HTTP bridge request');
}
if (request.headers['X-Source-Auth'] !== 'override') {
  throw new Error('URL option did not override the dynamic source header');
}
if (request.headers['X-Static'] !== 'source') {
  throw new Error('dynamic source header was not inherited by java.ajax');
}

payload.state.sourceHeaders = second.sourceHeaders;
payload.state.sourceHeaderResolution = second.sourceHeaderResolution;
payload.state.bridgeResponses[request.id] = {
  id: request.id,
  type: 'http',
  success: true,
  body: 'fixture-body',
  url: request.url,
  code: 200,
  headers: ''
};
const third = JSON.parse(runtimeContext.__manxiaLegadoRuntimeExecute(payload));
if (third.status !== 'ok' || third.result !== 'fixture-body') {
  throw new Error('bridge replay did not return the fixture response');
}

console.log(JSON.stringify({
  status: 'passed',
  contract: 'dynamic_source_header_inherited_by_java_ajax',
  sourceHeader: request.headers['X-Source-Auth'],
  inheritedHeader: request.headers['X-Static'],
  result: third.result
}));
