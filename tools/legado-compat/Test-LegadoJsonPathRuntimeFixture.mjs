import fs from 'node:fs';
import vm from 'node:vm';

const runtimeHtml = fs.readFileSync('entry/src/main/resources/rawfile/legado_runtime.html', 'utf8');
const fixture = JSON.parse(fs.readFileSync('tools/legado-compat/fixtures/legado-jsonpath-bridge.json', 'utf8'));
const scriptMatch = runtimeHtml.match(/<script>\s*([\s\S]*?)<\/script>/i);
if (!scriptMatch) throw new Error('legado runtime script is missing');

const runtimeContext = {
  window: {}, console, Date, Math, JSON, Object, Array, String, Number,
  RegExp, Error, TypeError, parseInt, parseFloat, isNaN,
  encodeURIComponent, decodeURIComponent, escape, unescape, Uint8Array, ArrayBuffer
};
runtimeContext.window = runtimeContext;
vm.createContext(runtimeContext);
runtimeContext.Function = vm.runInContext('Function', runtimeContext);
vm.runInContext(scriptMatch[1], runtimeContext);

const bodyText = JSON.stringify(fixture.body);
const payload = {
  code: [
    "var titles = java.getStringList('$.data[*].title', result);",
    "var thumbs = java.getStringList('$.data[*].data[0].thumb', result);",
    "var nested = java.getString('$.data[0].data', result);",
    "JSON.stringify({ titles: titles, thumbs: thumbs, nested: nested });"
  ].join('\n'),
  context: {
    result: bodyText,
    baseUrl: 'https://jsonpath-fixture.invalid',
    sourceUrl: 'https://jsonpath-fixture.invalid',
    variables: { sourceUrl: 'https://jsonpath-fixture.invalid' },
    source: {
      bookSourceUrl: 'https://jsonpath-fixture.invalid',
      bookSourceName: 'jsonpath-runtime-fixture',
      bookSourceType: '0'
    }
  },
  state: {
    bridgeResponses: {}, variables: { sourceUrl: 'https://jsonpath-fixture.invalid' },
    cache: {}, sourceData: {}, sourceHeaders: {}, sourceHeaderResolution: {},
    randomSeed: 1, now: 1700000000000
  }
};

const envelope = JSON.parse(runtimeContext.__manxiaLegadoRuntimeExecute(payload));
if (envelope.status !== 'ok') throw new Error(`runtime execution failed: ${JSON.stringify(envelope)}`);
const result = JSON.parse(envelope.result);
const expected = {
  titles: fixture.expected,
  thumbs: fixture.nestedExpected,
  nested: JSON.stringify(fixture.body.data[0].data)
};
if (JSON.stringify(result) !== JSON.stringify(expected)) {
  throw new Error(`JSONPath result mismatch: expected=${JSON.stringify(expected)} actual=${JSON.stringify(result)}`);
}

console.log(JSON.stringify({
  status: 'passed',
  contract: 'legado_jsonpath_runtime_execution',
  assertions: 6,
  result,
  fixture: 'tools/legado-compat/fixtures/legado-jsonpath-bridge.json'
}));
