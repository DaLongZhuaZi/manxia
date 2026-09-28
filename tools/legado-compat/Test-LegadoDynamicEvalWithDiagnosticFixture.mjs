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
  TypeError,
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

const payload = {
  code: 'eval(String(source.bookSourceComment))',
  context: {
    baseUrl: 'http://fixture.test',
    sourceUrl: 'http://fixture.test',
    variables: { sourceUrl: 'http://fixture.test' },
    source: {
      bookSourceUrl: 'http://fixture.test',
      bookSourceName: 'dynamic-eval-diagnostic-fixture',
      bookSourceType: '0',
      bookSourceComment: 'throw new TypeError("fixture_eval_inner_failure")'
    }
  },
  state: {
    bridgeResponses: {},
    variables: { sourceUrl: 'http://fixture.test' },
    cache: {},
    sourceData: {},
    sourceHeaders: {},
    sourceHeaderResolution: {},
    randomSeed: 1,
    now: 1700000000000
  }
};

const envelope = JSON.parse(runtimeContext.__manxiaLegadoRuntimeExecute(payload));
if (envelope.status !== 'error') {
  throw new Error(`expected dynamic eval failure, got ${JSON.stringify(envelope)}`);
}
if (typeof envelope.diagnostic !== 'string' || envelope.diagnostic.length === 0) {
  throw new Error(`expected structural runtime diagnostic, got ${JSON.stringify(envelope)}`);
}

console.log(JSON.stringify({
  status: 'fixture_failed_as_expected',
  diagnostic: envelope.diagnostic
}));
