import fs from 'node:fs';
import vm from 'node:vm';

const runtimeHtml = fs.readFileSync('entry/src/main/resources/rawfile/legado_runtime.html', 'utf8');
const scriptMatch = runtimeHtml.match(/<script>\s*([\s\S]*?)<\/script>/i);
if (!scriptMatch) {
  throw new Error('legado runtime script is missing');
}

class FixtureElement {
  constructor(title) {
    this.title = title;
    this.textContent = title;
    this.innerHTML = title;
    this.outerHTML = `<div class="category-item" title="${title}">${title}</div>`;
    this.parentElement = null;
  }

  getAttribute(name) {
    return String(name).toLowerCase() === 'title' ? this.title : null;
  }

  querySelectorAll(selector) {
    return String(selector) === '.category-item' ? [this] : [];
  }

  remove() {
    return undefined;
  }
}

class FixtureDocument {
  constructor(html) {
    this.html = String(html || '');
  }

  querySelectorAll(selector) {
    if (String(selector) !== '.category-item') {
      return [];
    }
    const values = [];
    const pattern = /class=["'][^"']*category-item[^"']*["'][^>]*title=["']([^"']+)["']/gi;
    let match = pattern.exec(this.html);
    while (match) {
      values.push(new FixtureElement(match[1]));
      match = pattern.exec(this.html);
    }
    return values;
  }
}

class FixtureDomParser {
  parseFromString(html) {
    return new FixtureDocument(html);
  }
}

const runtimeContext = {
  window: {},
  DOMParser: FixtureDomParser,
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

const sourceComment = 'r=org.jsoup.Jsoup.parse(java.ajax("http://fixture.test/categories/"));a=r.select(".category-item");name=[];for(i in a){name.push(a[i].attr("title"));}JSON.stringify(name)';
const payload = {
  code: 'eval(String(source.bookSourceComment));JSON.stringify(name)',
  context: {
    baseUrl: 'http://fixture.test',
    sourceUrl: 'http://fixture.test',
    variables: { sourceUrl: 'http://fixture.test' },
    source: {
      bookSourceUrl: 'http://fixture.test',
      bookSourceName: 'dynamic-explore-jsoup-fixture',
      bookSourceType: '0',
      bookSourceComment: sourceComment,
      enabledCookieJar: false
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

const first = JSON.parse(runtimeContext.__manxiaLegadoRuntimeExecute(payload));
if (first.status !== 'pending' || first.bridgeRequests.length !== 1 || first.bridgeRequests[0].type !== 'http') {
  throw new Error(`expected pending HTTP bridge, got ${JSON.stringify(first)}`);
}

const request = first.bridgeRequests[0];
payload.state.bridgeResponses[request.id] = {
  id: request.id,
  type: 'http',
  success: true,
  body: '<div class="category-item" title="分类一">分类一</div><div class="category-item" title="分类二">分类二</div>',
  url: request.url,
  code: 200,
  headers: ''
};

const second = JSON.parse(runtimeContext.__manxiaLegadoRuntimeExecute(payload));
if (second.status !== 'ok' || second.result !== '["分类一","分类二"]') {
  throw new Error(`dynamic explore Jsoup replay failed: ${JSON.stringify(second)}`);
}

console.log(JSON.stringify({
  status: 'passed',
  contract: 'dynamic_explore_jsoup_ajax_for_in_attr',
  result: second.result
}));
