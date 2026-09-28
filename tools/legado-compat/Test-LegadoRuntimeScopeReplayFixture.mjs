import fs from 'node:fs';
import vm from 'node:vm';

const runtimeHtml = fs.readFileSync('entry/src/main/resources/rawfile/legado_runtime.html', 'utf8');
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

function payload(code) {
  return {
    code,
    context: {
      baseUrl: 'http://scope-fixture.test',
      sourceUrl: 'http://scope-fixture.test',
      variables: { sourceUrl: 'http://scope-fixture.test' },
      source: {
        bookSourceUrl: 'http://scope-fixture.test',
        bookSourceName: 'scope-replay-fixture',
        bookSourceType: '0'
      }
    },
    state: {
      bridgeResponses: {}, variables: { sourceUrl: 'http://scope-fixture.test' },
      cache: {}, sourceData: {}, sourceHeaders: {}, sourceHeaderResolution: {},
      randomSeed: 1, now: 1700000000000
    }
  };
}

const firstPayload = payload("runtimeFixtureLeak = 'must-not-survive'; 1 + 1");
const first = JSON.parse(runtimeContext.__manxiaLegadoRuntimeExecute(firstPayload));
if (first.status !== 'ok' || first.result !== '2') {
  throw new Error(`first scope execution failed: ${JSON.stringify(first)}`);
}
const second = JSON.parse(runtimeContext.__manxiaLegadoRuntimeExecute(payload('typeof runtimeFixtureLeak')));
if (second.status !== 'ok' || second.result !== 'undefined') {
  throw new Error(`rule-local assignment leaked across executions: ${JSON.stringify(second)}`);
}

console.log(JSON.stringify({
  status: 'passed',
  contract: 'source_scoped_rule_assignment_isolation',
  firstResult: first.result,
  secondResult: second.result
}));
