# 图源浏览器控制台测试脚本

用法：

1. 先打开对应图源站点的任意页面。
2. 打开浏览器控制台。
3. 先执行“通用 Helper”。
4. 再执行对应图源脚本。
5. 最后执行示例里的 `await ...` 命令。

回传给我时，直接贴控制台返回对象或报错即可。

## 通用 Helper

```js
window.MX = (() => {
  const parser = new DOMParser();
  const clean = (value) => String(value ?? "").replace(/\s+/g, " ").trim();

  const abs = (value, base = location.origin) => {
    if (!value) return "";
    try {
      return new URL(value, base).href;
    } catch {
      return String(value);
    }
  };

  const pathOnly = (value, base = location.origin) => {
    if (!value) return "";
    try {
      const url = new URL(value, base);
      return `${url.pathname}${url.search}${url.hash}`;
    } catch {
      return String(value);
    }
  };

  const toDoc = (html) => parser.parseFromString(html, "text/html");

  const bgImage = (style = "") => {
    const match = String(style).match(/url\((['"]?)(.*?)\1\)/i);
    return match ? match[2] : "";
  };

  const uniqueBy = (list, keyFn) => {
    const seen = new Set();
    return list.filter((item) => {
      const key = keyFn(item);
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  };

  const selectorStats = (root, selectors) =>
    Object.fromEntries(selectors.map((selector) => [selector, root.querySelectorAll(selector).length]));

  const sample = (list, size = 5) => (Array.isArray(list) ? list.slice(0, size) : list);

  const mergeHeaders = (...parts) => {
    const headers = new Headers();
    for (const part of parts) {
      if (!part) continue;
      const entries = part instanceof Headers ? part.entries() : Object.entries(part);
      for (const [key, value] of entries) {
        if (value !== undefined && value !== null && value !== "") {
          headers.set(key, value);
        }
      }
    }
    return headers;
  };

  const request = async (url, init = {}) => {
    const response = await fetch(url, {
      credentials: "include",
      cache: "no-store",
      ...init,
    });
    const text = await response.text();
    return {
      ok: response.ok,
      status: response.status,
      requestedUrl: typeof url === "string" ? abs(url) : String(url),
      finalUrl: response.url,
      headers: Object.fromEntries(response.headers.entries()),
      text,
    };
  };

  const getDoc = async (url, init = {}) => {
    const response = await request(url, init);
    return { ...response, doc: toDoc(response.text) };
  };

  const getJson = async (url, init = {}) => {
    const response = await request(url, init);
    let json = null;
    let parseError = "";
    try {
      json = JSON.parse(response.text);
    } catch (error) {
      parseError = String(error);
    }
    return { ...response, json, parseError };
  };

  const postForm = async (url, data = {}, init = {}) => {
    const body = new URLSearchParams();
    for (const [key, value] of Object.entries(data)) {
      if (value !== undefined && value !== null) {
        body.append(key, String(value));
      }
    }
    return getJson(url, {
      ...init,
      method: "POST",
      headers: mergeHeaders(
        {
          "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
        },
        init.headers,
      ),
      body: body.toString(),
    });
  };

  const report = (label, payload) => {
    console.group(label);
    console.log(payload);
    console.groupEnd();
    return payload;
  };

  const firstSuccessful = async (candidates, loader, isGood) => {
    const attempts = [];
    for (const candidate of candidates) {
      try {
        const value = await loader(candidate);
        const good = isGood(value);
        attempts.push({ candidate, good, value });
        if (good) return { candidate, value, attempts };
      } catch (error) {
        attempts.push({ candidate, good: false, error: String(error) });
      }
    }
    return { candidate: "", value: null, attempts };
  };

  return {
    clean,
    abs,
    pathOnly,
    toDoc,
    bgImage,
    uniqueBy,
    selectorStats,
    sample,
    mergeHeaders,
    request,
    getDoc,
    getJson,
    postForm,
    report,
    firstSuccessful,
  };
})();
```

## Photos18

```js
window.MXPhotos18 = (() => {
  const mx = window.MX;
  const base = location.origin;
  const defaultLang = "/zh-hans";

  const normalizeGallery = (value) => {
    let raw = mx.pathOnly(value, base).replace(/^\/zh-hans/, "");
    raw = raw.replace(/^\/+/, "");
    raw = raw.replace(/^v\//, "");
    return { slug: raw, path: `/v/${raw}` };
  };

  const normalizeItemPath = (href) => mx.pathOnly(href, base).replace(/^\/zh-hans/, "");

  const parseCard = (card) => {
    const cardBody = card.querySelector(".card-body");
    const link = cardBody?.querySelector("a");
    if (!link) return null;
    const path = normalizeItemPath(link.getAttribute("href") || "");
    const slug = path.replace(/^\/v\//, "");
    const img = card.querySelector("img");
    const label = cardBody?.querySelector("label");
    return {
      id: slug,
      path,
      title: mx.clean(link.textContent),
      cover: mx.abs(
        img?.getAttribute("src") ||
          img?.getAttribute("data-src") ||
          img?.getAttribute("data-lazy-src") ||
          "",
        base,
      ),
      genre: mx.clean(label?.textContent),
      url: mx.abs(path, base),
    };
  };

  const parseList = (doc) => {
    const container = doc.querySelector("#videos");
    if (!container) return [];
    return [...container.querySelectorAll(".card")].map(parseCard).filter(Boolean);
  };

  const parsePages = (doc) =>
    [...doc.querySelectorAll("#content img")]
      .map((img, index) => ({
        index,
        url: mx.abs(
          img.getAttribute("src") ||
            img.getAttribute("data-src") ||
            img.getAttribute("data-lazy-src") ||
            "",
          base,
        ),
      }))
      .filter((page) => page.url);

  return {
    async popular(page = 1, lang = defaultLang) {
      const response = await mx.getDoc(`${base}${lang}/sort/views?page=${page}`);
      const items = parseList(response.doc);
      return mx.report("[Photos18] popular", {
        url: response.finalUrl,
        status: response.status,
        selectors: mx.selectorStats(response.doc, ["#videos", "#videos .card", ".next"]),
        count: items.length,
        hasNextPage:
          !!response.doc.querySelector(".next") &&
          !response.doc.querySelector(".next")?.classList.contains("disabled"),
        sample: mx.sample(items),
      });
    },

    async latest(page = 1, lang = defaultLang) {
      const url =
        page <= 1
          ? `${base}${lang}/`
          : `${base}${lang}?page=${page}&per-page=100`;
      const response = await mx.getDoc(url);
      const items = parseList(response.doc);
      return mx.report("[Photos18] latest", {
        url: response.finalUrl,
        status: response.status,
        selectors: mx.selectorStats(response.doc, ["#videos", "#videos .card", ".next"]),
        count: items.length,
        hasNextPage:
          !!response.doc.querySelector(".next") &&
          !response.doc.querySelector(".next")?.classList.contains("disabled"),
        sample: mx.sample(items),
      });
    },

    async search(query, page = 1, options = {}) {
      const lang = options.lang ?? defaultLang;
      const sort = options.sort ?? "views";
      const response = await mx.getDoc(
        `${base}${lang}/?q=${encodeURIComponent(query)}&page=${page}&sort=${encodeURIComponent(sort)}`,
      );
      const items = parseList(response.doc);
      return mx.report("[Photos18] search", {
        url: response.finalUrl,
        status: response.status,
        query,
        selectors: mx.selectorStats(response.doc, ["#videos", "#videos .card"]),
        count: items.length,
        sample: mx.sample(items),
      });
    },

    async detail(mangaIdOrPath) {
      const normalized = normalizeGallery(mangaIdOrPath);
      const response = await mx.getDoc(`${base}${normalized.path}`);
      const pages = parsePages(response.doc);
      return mx.report("[Photos18] detail", {
        url: response.finalUrl,
        status: response.status,
        selectors: mx.selectorStats(response.doc, ["h1", "#content img"]),
        detail: {
          id: normalized.slug,
          path: normalized.path,
          title:
            mx.clean(response.doc.querySelector("h1")?.textContent) ||
            mx.clean(response.doc.title).replace(/\s*-\s*Photos18.*$/i, ""),
          cover: pages[0]?.url || "",
          pageCount: pages.length,
          status: "completed",
        },
      });
    },

    async chapters(mangaIdOrPath) {
      const normalized = normalizeGallery(mangaIdOrPath);
      return mx.report("[Photos18] chapters", {
        manga: normalized,
        chapters: [
          {
            id: normalized.slug,
            path: normalized.path,
            title: "Gallery",
            url: `${base}${normalized.path}`,
          },
        ],
      });
    },

    async pages(chapterIdOrPath) {
      const normalized = normalizeGallery(chapterIdOrPath);
      const response = await mx.getDoc(`${base}${normalized.path}`);
      const pages = parsePages(response.doc);
      return mx.report("[Photos18] pages", {
        url: response.finalUrl,
        status: response.status,
        selectors: mx.selectorStats(response.doc, ["#content", "#content img"]),
        count: pages.length,
        sample: mx.sample(pages),
      });
    },
  };
})();
```

先测：

```js
await MXPhotos18.latest(1);
```

补充：

```js
await MXPhotos18.popular(1);
await MXPhotos18.search("miya", 1);
await MXPhotos18.detail("/v/xxx");
await MXPhotos18.pages("/v/xxx");
```

## Everia.club

```js
window.MXEveria = (() => {
  const mx = window.MX;
  const base = location.origin;

  const normalizePost = (value) => {
    let raw = mx.pathOnly(value, base);
    raw = raw.replace(/^\/+/, "").replace(/\/+$/, "");
    return { slug: raw, path: `/${raw}/` };
  };

  const imgSrc = (img) =>
    mx.abs(
      img?.getAttribute("data-lazy-src") ||
        img?.getAttribute("data-src") ||
        img?.getAttribute("src") ||
        "",
      base,
    );

  const parseLatestItem = (article) => {
    const link = article.querySelector(".entry-title > a");
    if (!link) return null;
    const normalized = normalizePost(link.getAttribute("href") || "");
    return {
      id: normalized.slug,
      path: normalized.path,
      title: mx.clean(article.querySelector(".entry-title")?.textContent),
      cover: imgSrc(article.querySelector("img")),
      url: mx.abs(normalized.path, base),
    };
  };

  const parsePopularItem = (item) => {
    const link = item.querySelector("h3 > a");
    if (!link) return null;
    const normalized = normalizePost(link.getAttribute("href") || "");
    return {
      id: normalized.slug,
      path: normalized.path,
      title: mx.clean(item.querySelector("h3")?.textContent),
      cover: imgSrc(item.querySelector("img")),
      url: mx.abs(normalized.path, base),
    };
  };

  const parsePages = (doc) => {
    doc.querySelectorAll("noscript").forEach((node) => node.remove());
    return [...doc.querySelectorAll(".entry-content img")]
      .map((img, index) => ({ index, url: imgSrc(img) }))
      .filter((page) => page.url);
  };

  const extractDateFromUrl = (url) => {
    const match = String(url).match(/\b(\d{4})\/(\d{2})\/(\d{2})\b/);
    return match ? `${match[1]}-${match[2]}-${match[3]}` : "";
  };

  return {
    async latest(page = 1) {
      const response = await mx.getDoc(page <= 1 ? `${base}/` : `${base}/page/${page}/`);
      const items = [...response.doc.querySelectorAll("#blog-entries > article")]
        .map(parseLatestItem)
        .filter(Boolean);
      return mx.report("[Everia] latest", {
        url: response.finalUrl,
        status: response.status,
        selectors: mx.selectorStats(response.doc, ["#blog-entries > article", ".next"]),
        count: items.length,
        hasNextPage: !!response.doc.querySelector(".next"),
        sample: mx.sample(items),
      });
    },

    async popular(page = 1) {
      const response = await mx.getDoc(page <= 1 ? `${base}/` : `${base}/page/${page}/`);
      const items = [...response.doc.querySelectorAll(".wli_popular_posts-class li")]
        .map(parsePopularItem)
        .filter(Boolean);
      return mx.report("[Everia] popular", {
        url: response.finalUrl,
        status: response.status,
        selectors: mx.selectorStats(response.doc, [".wli_popular_posts-class li"]),
        count: items.length,
        sample: mx.sample(items),
      });
    },

    async search(query, page = 1) {
      const response = await mx.getDoc(`${base}/?paged=${page}&s=${encodeURIComponent(query)}`);
      const items = [...response.doc.querySelectorAll("#content > article")]
        .map(parseLatestItem)
        .filter(Boolean);
      return mx.report("[Everia] search", {
        url: response.finalUrl,
        status: response.status,
        query,
        selectors: mx.selectorStats(response.doc, ["#content > article", ".next"]),
        count: items.length,
        sample: mx.sample(items),
      });
    },

    async detail(mangaIdOrPath) {
      const normalized = normalizePost(mangaIdOrPath);
      const response = await mx.getDoc(`${base}${normalized.path}`);
      return mx.report("[Everia] detail", {
        url: response.finalUrl,
        status: response.status,
        selectors: mx.selectorStats(response.doc, [".entry-title", ".post-tags > a", ".entry-content img"]),
        detail: {
          id: normalized.slug,
          path: normalized.path,
          title: mx.clean(response.doc.querySelector(".entry-title")?.textContent),
          description: mx.clean(response.doc.querySelector(".entry-title")?.textContent),
          genre: [...response.doc.querySelectorAll(".post-tags > a")]
            .map((el) => mx.clean(el.textContent))
            .join(", "),
          cover: imgSrc(response.doc.querySelector(".entry-content img, .wp-post-image, img")),
          status: "completed",
        },
      });
    },

    async chapters(mangaIdOrPath) {
      const normalized = normalizePost(mangaIdOrPath);
      const response = await mx.getDoc(`${base}${normalized.path}`);
      const canonical =
        response.doc.querySelector('link[rel="canonical"]')?.getAttribute("href") || response.finalUrl;
      return mx.report("[Everia] chapters", {
        url: response.finalUrl,
        status: response.status,
        chapters: [
          {
            id: normalizePost(canonical).slug,
            path: normalizePost(canonical).path,
            title: "Gallery",
            date: extractDateFromUrl(canonical),
          },
        ],
      });
    },

    async pages(chapterIdOrPath) {
      const normalized = normalizePost(chapterIdOrPath);
      const response = await mx.getDoc(`${base}${normalized.path}`);
      const pages = parsePages(response.doc);
      return mx.report("[Everia] pages", {
        url: response.finalUrl,
        status: response.status,
        selectors: mx.selectorStats(response.doc, [".entry-content img", "noscript"]),
        count: pages.length,
        sample: mx.sample(pages),
      });
    },
  };
})();
```

先测：

```js
await MXEveria.popular(1);
```

补充：

```js
await MXEveria.latest(1);
await MXEveria.search("miya", 1);
await MXEveria.detail("2024/01/01/example-post");
await MXEveria.pages("2024/01/01/example-post");
```

## WNACG / 绅士漫画

```js
window.MXWNACG = (() => {
  const mx = window.MX;
  const base = location.origin;

  const normalizePath = (value) => {
    let raw = mx.pathOnly(value, base);
    if (!raw.startsWith("/")) raw = `/${raw}`;
    return raw.replace(/\/+$/, "");
  };

  const coverUrl = (img) => {
    let value =
      img?.getAttribute("src") ||
      img?.getAttribute("data-original") ||
      img?.getAttribute("data-src") ||
      "";
    if (value.startsWith("//")) value = `http:${value}`;
    return mx.abs(value, base);
  };

  const parseItem = (element) => {
    const link =
      element.querySelector(".title > a") ||
      element.querySelector("a[href*='photos-index']");
    if (!link) return null;
    const path = normalizePath(link.getAttribute("href") || "");
    return {
      id: path,
      path,
      title: mx.clean(link.textContent || link.getAttribute("title")),
      cover: coverUrl(element.querySelector("img")),
      url: mx.abs(path, base),
    };
  };

  const parseList = (doc) =>
    [...doc.querySelectorAll(".gallary_item")]
      .map(parseItem)
      .filter(Boolean);

  const normalizeGalleryPath = (value) =>
    normalizePath(value).replace("-index-", "-gallery-");

  const normalizeSlistPath = (value) =>
    normalizePath(value).replace("-index-", "-slist-");

  const extractImageUrls = (text) => {
    const regex = /\/\/\S+\.(?:jpeg|jpg|png|webp|gif)/gi;
    const matches = [...text.matchAll(regex)];
    return matches.map((match, index) => ({ index, url: `http:${match[0]}` }));
  };

  const extractSlistImages = (doc) =>
    mx.uniqueBy(
      [...doc.querySelectorAll("img")]
        .map((img, index) => {
          let value =
            img.getAttribute("src") ||
            img.getAttribute("data-original") ||
            img.getAttribute("data-src") ||
            "";
          if (value.startsWith("//")) value = `http:${value}`;
          return { index, url: mx.abs(value, base) };
        })
        .filter((page) => /\/data\//.test(page.url) && !/\/data\/t\//.test(page.url)),
      (page) => page.url,
    ).map((page, index) => ({ ...page, index }));

  return {
    async popular(page = 1) {
      const response = await mx.getDoc(`${base}/albums-index-page-${page}.html`);
      const items = parseList(response.doc);
      return mx.report("[WNACG] popular", {
        url: response.finalUrl,
        status: response.status,
        selectors: mx.selectorStats(response.doc, [".gallary_item", "span.thispage + a"]),
        count: items.length,
        hasNextPage: !!response.doc.querySelector("span.thispage + a"),
        sample: mx.sample(items),
      });
    },

    async search(query, page = 1) {
      const response = await mx.getDoc(
        `${base}/search/index.php?s=create_time_DESC&q=${encodeURIComponent(query)}&p=${page}`,
      );
      const items = parseList(response.doc);
      return mx.report("[WNACG] search", {
        url: response.finalUrl,
        status: response.status,
        query,
        selectors: mx.selectorStats(response.doc, [".gallary_item", "span.thispage + a"]),
        count: items.length,
        hasNextPage: !!response.doc.querySelector("span.thispage + a"),
        sample: mx.sample(items),
      });
    },

    async category(template, page = 1) {
      const path = String(template).replace("%d", String(page)).replace(/^\/+/, "");
      const response = await mx.getDoc(`${base}/${path}`);
      const items = parseList(response.doc);
      return mx.report("[WNACG] category", {
        url: response.finalUrl,
        status: response.status,
        template,
        selectors: mx.selectorStats(response.doc, [".gallary_item", "span.thispage + a"]),
        count: items.length,
        sample: mx.sample(items),
      });
    },

    async tag(tag, page = 1) {
      const encoded = encodeURIComponent(tag);
      const candidates = [
        `/albums-index-page-${page}-tag-${encoded}`,
        `/albums-index-page-${page}-tag-${encoded}.html`,
      ];
      const results = [];
      for (const path of candidates) {
        const response = await mx.getDoc(`${base}${path}`);
        const items = parseList(response.doc);
        results.push({
          path,
          finalUrl: response.finalUrl,
          status: response.status,
          selectors: mx.selectorStats(response.doc, [".gallary_item", ".title > a"]),
          count: items.length,
          sample: mx.sample(items),
        });
      }
      return mx.report("[WNACG] tag", { tag, results });
    },

    async detail(mangaPath) {
      const path = normalizePath(mangaPath);
      const response = await mx.getDoc(`${base}${path}`);
      let cover = response.doc.querySelector("div.uwthumb img")?.getAttribute("src") || "";
      if (cover.startsWith("//")) cover = `http:${cover}`;
      return mx.report("[WNACG] detail", {
        url: response.finalUrl,
        status: response.status,
        selectors: mx.selectorStats(response.doc, ["h2", "div.uwuinfo p", "div.uwthumb img", "a.tagshow"]),
        detail: {
          id: path,
          path,
          title: mx.clean(response.doc.querySelector("h2")?.textContent),
          author: mx.clean(response.doc.querySelector("div.uwuinfo p")?.textContent),
          artist: mx.clean(response.doc.querySelector("div.uwuinfo p")?.textContent),
          genre: [...response.doc.querySelectorAll("a.tagshow")].map((el) => mx.clean(el.textContent)).join(", "),
          cover: mx.abs(cover, base),
          description: mx.clean(
            response.doc.querySelector("div.asTBcell p")?.innerHTML?.replace(/<br\s*\/?>/gi, "\n"),
          ),
          status: "completed",
        },
      });
    },

    async chapters(mangaPath) {
      const path = normalizePath(mangaPath);
      return mx.report("[WNACG] chapters", {
        mangaPath: path,
        chapters: [{ id: path, path, title: "Ch. 1", url: `${base}${path}` }],
      });
    },

    async pages(mangaPath) {
      const inputPath = normalizePath(mangaPath);
      const galleryPath = normalizeGalleryPath(inputPath);
      const slistPath = normalizeSlistPath(inputPath);
      const galleryResponse = await mx.request(`${base}${galleryPath}`);
      const galleryPages = extractImageUrls(galleryResponse.text);
      const slistResponse = await mx.getDoc(`${base}${slistPath}`);
      const slistPages = extractSlistImages(slistResponse.doc);
      return mx.report("[WNACG] pages", {
        inputPath,
        gallery: {
          path: galleryPath,
          finalUrl: galleryResponse.finalUrl,
          status: galleryResponse.status,
          count: galleryPages.length,
          sample: mx.sample(galleryPages),
        },
        slist: {
          path: slistPath,
          finalUrl: slistResponse.finalUrl,
          status: slistResponse.status,
          selectors: mx.selectorStats(slistResponse.doc, ["img", "img[data-original]", "img[data-src]"]),
          count: slistPages.length,
          sample: mx.sample(slistPages),
        },
      });
    },
  };
})();
```

先测：

```js
await MXWNACG.popular(1);
```

补充：

```js
await MXWNACG.search("FGO", 1);
await MXWNACG.category("albums-index-page-%d-cate-5.html", 1);
await MXWNACG.tag("巨乳", 1);
await MXWNACG.detail("/photos-index-aid-123456.html");
await MXWNACG.pages("/photos-index-aid-123456.html");
```

## Manwa / 漫蛙

```js
window.MXManwa = (() => {
  const mx = window.MX;
  const base = location.origin;

  const imgSrc = (img) =>
    mx.abs(
      img?.getAttribute("data-original") ||
        img?.getAttribute("src") ||
        img?.getAttribute("data-src") ||
        "",
      base,
    );

  const normalizeChapterPath = (value) => {
    let raw = mx.pathOnly(value, base);
    if (!raw.startsWith("/")) raw = `/${raw}`;
    return raw.replace(/\/+$/, "");
  };

  const normalizeMangaCandidates = (value) => {
    let raw = mx.pathOnly(value, base);
    raw = raw.replace(/\/+$/, "");
    raw = raw.replace(/^\/+/, "");
    if (!raw) return [];
    const numeric = raw.replace(/^book\//, "").replace(/^\/+/, "");
    const candidates = [];
    if (raw.startsWith("book/")) candidates.push(`/${raw}`);
    if (raw.startsWith("book/")) candidates.push(`/${numeric}`);
    if (/^\d+$/.test(numeric)) {
      candidates.push(`/${numeric}`);
      candidates.push(`/book/${numeric}`);
    }
    if (raw.startsWith("chapter/")) candidates.push(`/${raw}`);
    return [...new Set(candidates.filter(Boolean))];
  };

  const parsePopularItem = (anchor) => ({
    id: mx.pathOnly(anchor.getAttribute("href") || "", base),
    path: mx.pathOnly(anchor.getAttribute("href") || "", base),
    title: mx.clean(anchor.getAttribute("title") || anchor.textContent),
    cover: imgSrc(anchor.querySelector("img")),
    url: mx.abs(anchor.getAttribute("href") || "", base),
  });

  const parseSearchBookItem = (li) => ({
    id: mx.pathOnly(li.querySelector("a")?.getAttribute("href") || "", base),
    path: mx.pathOnly(li.querySelector("a")?.getAttribute("href") || "", base),
    title: mx.clean(li.querySelector("p.book-list-info-title")?.textContent),
    cover: imgSrc(li.querySelector("img")),
    url: mx.abs(li.querySelector("a")?.getAttribute("href") || "", base),
  });

  const parseBrowseItem = (li) => ({
    id: mx.pathOnly(li.querySelector("a")?.getAttribute("href") || "", base),
    path: mx.pathOnly(li.querySelector("a")?.getAttribute("href") || "", base),
    title: mx.clean(li.querySelector("p.manga-list-2-title")?.textContent),
    cover: imgSrc(li.querySelector("img")),
    url: mx.abs(li.querySelector("a")?.getAttribute("href") || "", base),
  });

  const parseStatus = (doc) => {
    const rows = [...doc.querySelectorAll("p.detail-main-info-author")].map((row) => mx.clean(row.textContent));
    const hit = rows.find((row) => row.includes("更新状态") || row.includes("狀態"));
    if (!hit) return "unknown";
    if (hit.includes("连载") || hit.includes("連載")) return "ongoing";
    if (hit.includes("完结") || hit.includes("完結")) return "completed";
    return "unknown";
  };

  const parseDetail = (doc) => ({
    title: mx.clean(doc.querySelector(".detail-main-info-title")?.textContent),
    cover: imgSrc(doc.querySelector("div.detail-main-cover > img")),
    author: mx.clean(doc.querySelector("p.detail-main-info-author span.detail-main-info-value a")?.textContent),
    status: parseStatus(doc),
    genre: [...doc.querySelectorAll("div.detail-main-info-class a.info-tag, div.detail-main-info-class span.info-tag-span")]
      .map((el) => mx.clean(el.textContent))
      .filter(Boolean)
      .join(", "),
    description: mx.clean(doc.querySelector("#detail > p.detail-desc")?.textContent),
  });

  const parseChapters = (doc) =>
    [...doc.querySelectorAll("ul#detail-list-select > li > a")]
      .map((link) => ({
        id: mx.pathOnly(link.getAttribute("href") || "", base),
        path: mx.pathOnly(link.getAttribute("href") || "", base),
        title: mx.clean(link.textContent),
        url: mx.abs(link.getAttribute("href") || "", base),
      }))
      .reverse();

  const parsePages = (doc) =>
    [...doc.querySelectorAll("#cp_img > div.img-content > img[data-r-src], #cp_img img[data-r-src]")]
      .map((img, index) => ({
        index,
        url: mx.abs(img.getAttribute("data-r-src") || img.getAttribute("src") || "", base),
      }))
      .filter((page) => page.url && !page.url.startsWith("data:"));

  const parseLatestImageHost = (doc) => {
    const value = doc.querySelector(".manga-list-2-cover-img")?.getAttribute(":src") || "";
    if (!value.startsWith("'")) return "";
    return value.slice(1).split("'")[0] || "";
  };

  return {
    async imageHostOptions() {
      const response = await mx.getDoc(`${base}/`);
      const options = [...response.doc.querySelectorAll("#img-host-modal > div.modal-body a")].map((a) => ({
        name: mx.clean(a.textContent),
        param: a.getAttribute("href") || "",
      }));
      return mx.report("[Manwa] imageHostOptions", {
        url: response.finalUrl,
        status: response.status,
        selectors: mx.selectorStats(response.doc, ["#img-host-modal > div.modal-body a"]),
        count: options.length,
        options,
      });
    },

    async latest(page = 1, imageHostParam = "") {
      const offset = page * 15 - 15;
      const apiResponse = await mx.getJson(`${base}/getUpdate?page=${offset}&date=`);
      const imageHostResponse = await mx.getDoc(`${base}/update${imageHostParam}`);
      const imageHost = parseLatestImageHost(imageHostResponse.doc);
      const books = Array.isArray(apiResponse.json?.books) ? apiResponse.json.books : [];
      const items = books.map((item) => ({
        id: String(item.id),
        bookPath: `/book/${item.id}`,
        rootPath: `/${item.id}`,
        title: item.book_name || "",
        cover: imageHost ? `${imageHost}${item.cover_url || ""}` : String(item.cover_url || ""),
      }));
      return mx.report("[Manwa] latest", {
        apiUrl: apiResponse.finalUrl,
        apiStatus: apiResponse.status,
        imageHostUrl: imageHostResponse.finalUrl,
        imageHostStatus: imageHostResponse.status,
        imageHost,
        parseError: apiResponse.parseError,
        total: apiResponse.json?.total,
        count: items.length,
        sample: mx.sample(items),
      });
    },

    async popular() {
      const response = await mx.getDoc(`${base}/rank`);
      const items = [...response.doc.querySelectorAll("#rankList_2 > a")].map(parsePopularItem);
      return mx.report("[Manwa] popular", {
        url: response.finalUrl,
        status: response.status,
        selectors: mx.selectorStats(response.doc, ["#rankList_2 > a", "#rankList_2 img"]),
        count: items.length,
        sample: mx.sample(items),
      });
    },

    async searchKeyword(query, page = 1) {
      const suffix = page > 1 ? `&page=${page}` : "";
      const response = await mx.getDoc(`${base}/search?keyword=${encodeURIComponent(query)}${suffix}`);
      const items = [...response.doc.querySelectorAll("ul.book-list > li")]
        .map(parseSearchBookItem)
        .filter((item) => item.title && item.path);
      return mx.report("[Manwa] searchKeyword", {
        url: response.finalUrl,
        status: response.status,
        query,
        selectors: mx.selectorStats(response.doc, ["ul.book-list > li", "p.book-list-info-title", "ul.pagination2 > li"]),
        count: items.length,
        sample: mx.sample(items),
      });
    },

    async browse(filters = {}, page = 1) {
      const url = new URL(`${base}/booklist`);
      url.searchParams.set("end", filters.end ?? "");
      url.searchParams.set("gender", filters.gender ?? "-1");
      url.searchParams.set("area", filters.area ?? "");
      url.searchParams.set("sort", filters.sort ?? "-1");
      url.searchParams.set("tag", filters.tag ?? "");
      if (page > 1) url.searchParams.set("page", String(page));
      const response = await mx.getDoc(url.toString());
      const items = [...response.doc.querySelectorAll("ul.manga-list-2 > li")]
        .map(parseBrowseItem)
        .filter((item) => item.title && item.path);
      return mx.report("[Manwa] browse", {
        url: response.finalUrl,
        status: response.status,
        filters,
        selectors: mx.selectorStats(response.doc, ["ul.manga-list-2 > li", "p.manga-list-2-title", "ul.pagination2 > li"]),
        count: items.length,
        sample: mx.sample(items),
      });
    },

    async detail(mangaIdOrPath) {
      const candidates = normalizeMangaCandidates(mangaIdOrPath);
      const result = await mx.firstSuccessful(
        candidates,
        async (path) => {
          const response = await mx.getDoc(`${base}${path}`);
          return { path, response, detail: parseDetail(response.doc) };
        },
        (value) => Boolean(value?.detail?.title),
      );
      return mx.report("[Manwa] detail", {
        input: mangaIdOrPath,
        attempts: result.attempts.map((attempt) => ({
          candidate: attempt.candidate,
          good: attempt.good,
          status: attempt.value?.response?.status,
          title: attempt.value?.detail?.title || "",
        })),
        chosen: result.candidate,
        detail: result.value?.detail || null,
      });
    },

    async chapters(mangaIdOrPath) {
      const candidates = normalizeMangaCandidates(mangaIdOrPath);
      const result = await mx.firstSuccessful(
        candidates,
        async (path) => {
          const response = await mx.getDoc(`${base}${path}`);
          return { path, response, chapters: parseChapters(response.doc) };
        },
        (value) => Array.isArray(value?.chapters),
      );
      return mx.report("[Manwa] chapters", {
        input: mangaIdOrPath,
        attempts: result.attempts.map((attempt) => ({
          candidate: attempt.candidate,
          good: attempt.good,
          status: attempt.value?.response?.status,
          count: attempt.value?.chapters?.length ?? 0,
        })),
        chosen: result.candidate,
        count: result.value?.chapters?.length ?? 0,
        sample: mx.sample(result.value?.chapters ?? []),
      });
    },

    async pages(chapterPath, imageHostParam = "") {
      const path = normalizeChapterPath(chapterPath);
      const response = await mx.getDoc(`${base}${path}${imageHostParam}`, {
        headers: { rsc: "1" },
      });
      const pages = parsePages(response.doc);
      return mx.report("[Manwa] pages", {
        url: response.finalUrl,
        status: response.status,
        chapterPath: path,
        selectors: mx.selectorStats(response.doc, ["#cp_img", "#cp_img img", "#cp_img img[data-r-src]"]),
        count: pages.length,
        sample: mx.sample(pages),
      });
    },
  };
})();
```

先测：

```js
await MXManwa.imageHostOptions();
await MXManwa.latest(1);
await MXManwa.popular();
```

补充：

```js
await MXManwa.searchKeyword("老师", 1);
await MXManwa.browse({ end: "", gender: "-1", area: "", sort: "-1", tag: "" }, 1);
await MXManwa.detail("159321");
await MXManwa.chapters("159321");
await MXManwa.pages("/chapter/30284528");
```

## 肉漫屋 / Roumanwu

```js
window.MXRoumanwu = (() => {
  const mx = window.MX;
  const base = location.origin;

  const imgSrc = (img) =>
    mx.abs(
      img?.getAttribute("src") ||
        img?.getAttribute("data-src") ||
        img?.getAttribute("data-lazy-src") ||
        "",
      base,
    );

  const normalizeBookPath = (value) => {
    let raw = mx.pathOnly(value, base);
    raw = raw.replace(/\/+$/, "");
    raw = raw.replace(/^\/+/, "");
    if (!raw.startsWith("books/")) raw = `books/${raw}`;
    return `/${raw}`;
  };

  const normalizeChapterPath = (value) => normalizeBookPath(value);

  const parseEntryAnchor = (anchor) => {
    const href = anchor.getAttribute("href") || "";
    const path = normalizeBookPath(href);
    const title = mx.clean(anchor.querySelector("div.truncate")?.textContent);
    const cover =
      mx.bgImage(anchor.querySelector("div.bg-cover")?.getAttribute("style") || "") ||
      imgSrc(anchor.querySelector("img"));
    return {
      id: path,
      path,
      title,
      cover: mx.abs(cover, base),
      url: mx.abs(path, base),
    };
  };

  const parseEntries = (root) =>
    mx.uniqueBy(
      [...root.querySelectorAll("a[href*='/books/']")]
        .map(parseEntryAnchor)
        .filter((item) => item.title && item.path),
      (item) => item.path,
    );

  const parseSections = (doc, keywords) => {
    const sections = [...doc.querySelectorAll("div.px-1 > div")];
    const matched = sections.filter((section) => {
      const header = mx.clean(section.firstElementChild?.textContent);
      return keywords.some((keyword) => header.includes(keyword));
    });
    return mx.uniqueBy(matched.flatMap((section) => parseEntries(section)), (item) => item.path);
  };

  const infoboxTexts = (doc) =>
    [...(doc.querySelector("div.basis-3\\/5")?.children || [])].map((el) => mx.clean(el.textContent));

  const parseDetail = (doc) => {
    const rows = infoboxTexts(doc);
    const detail = {
      title: rows[0] || "",
      cover: imgSrc(doc.querySelector("div.basis-2\\/5 img")),
      author: "",
      status: "unknown",
      genre: "",
      description: "",
      updateTime: "",
    };
    const intro = [...doc.querySelectorAll("p")].find((p) => mx.clean(p.textContent).startsWith("简介"));
    if (intro) detail.description = mx.clean(intro.textContent.replace(/^简介[:：]/, ""));
    const genres = [];
    for (const row of rows) {
      if (row.startsWith("作者")) {
        detail.author = mx.clean(row.replace(/^作者[:：]/, ""));
      } else if (row.startsWith("状态")) {
        const value = mx.clean(row.replace(/^状态[:：]/, ""));
        if (value.includes("连载") || value.includes("連載")) detail.status = "ongoing";
        else if (value.includes("完结") || value.includes("完結")) detail.status = "completed";
      } else if (row.startsWith("地区")) {
        const value = mx.clean(row.replace(/^地区[:：]/, ""));
        if (value) genres.push(value);
      } else if (row.startsWith("标签")) {
        const value = mx.clean(row.replace(/^标签[:：]/, ""));
        if (value) genres.push(...value.split(",").map((x) => mx.clean(x)).filter(Boolean));
      }
      const dateMatch = row.match(/\b\d{1,2}\/\d{1,2}\/\d{4}\b/);
      if (dateMatch) detail.updateTime = dateMatch[0];
    }
    detail.genre = genres.join(", ");
    return detail;
  };

  const parseChapters = (doc) =>
    [...doc.querySelectorAll("a[href*='/books/']")]
      .map((a) => {
        const href = a.getAttribute("href") || "";
        const match = href.match(/\/books\/[^/\s?#]+\/\d+(?:[?#].*)?$/);
        if (!match) return null;
        return {
          id: normalizeChapterPath(href),
          path: normalizeChapterPath(href),
          title: mx.clean(a.textContent),
          url: mx.abs(href, base),
        };
      })
      .filter(Boolean)
      .reverse();

  const parsePagesFromHtml = (html) => {
    const regex = /"imageUrl":"([^"]+)"/g;
    const pages = [];
    let match;
    while ((match = regex.exec(html)) !== null) {
      pages.push({ index: pages.length, url: match[1] });
    }
    return pages;
  };

  return {
    async popular() {
      const response = await mx.getDoc(`${base}/home`);
      const items = parseSections(response.doc, ["正熱門", "今日最佳", "本週熱門"]);
      return mx.report("[Roumanwu] popular", {
        url: response.finalUrl,
        status: response.status,
        selectors: mx.selectorStats(response.doc, ["div.px-1 > div", "a[href*='/books/']"]),
        count: items.length,
        sample: mx.sample(items),
      });
    },

    async latest() {
      const response = await mx.getDoc(`${base}/home`);
      const items = parseSections(response.doc, ["最近更新"]);
      return mx.report("[Roumanwu] latest", {
        url: response.finalUrl,
        status: response.status,
        selectors: mx.selectorStats(response.doc, ["div.px-1 > div", "a[href*='/books/']"]),
        count: items.length,
        sample: mx.sample(items),
      });
    },

    async search(query, page = 1) {
      const zeroBasedPage = Math.max(0, page - 1);
      const response = await mx.getDoc(`${base}/search?term=${encodeURIComponent(query)}&page=${zeroBasedPage}`);
      const items = parseEntries(response.doc);
      return mx.report("[Roumanwu] search", {
        url: response.finalUrl,
        status: response.status,
        query,
        selectors: mx.selectorStats(response.doc, ["a[href*='/books/']", "div.justify-end > a"]),
        count: items.length,
        sample: mx.sample(items),
      });
    },

    async browse(page = 1, continued = "") {
      const zeroBasedPage = Math.max(0, page - 1);
      const suffix = continued === "" ? "" : `&continued=${continued}`;
      const response = await mx.getDoc(`${base}/books?page=${zeroBasedPage}${suffix}`);
      const items = parseEntries(response.doc);
      return mx.report("[Roumanwu] browse", {
        url: response.finalUrl,
        status: response.status,
        continued,
        selectors: mx.selectorStats(response.doc, ["a[href*='/books/']", "div.justify-end > a"]),
        count: items.length,
        sample: mx.sample(items),
      });
    },

    async detail(bookPath) {
      const path = normalizeBookPath(bookPath);
      const response = await mx.getDoc(`${base}${path}`);
      return mx.report("[Roumanwu] detail", {
        url: response.finalUrl,
        status: response.status,
        selectors: mx.selectorStats(response.doc, ["div.basis-2\\/5 img", "div.basis-3\\/5", "p"]),
        detail: parseDetail(response.doc),
      });
    },

    async chapters(bookPath) {
      const path = normalizeBookPath(bookPath);
      const response = await mx.getDoc(`${base}${path}`);
      const chapters = parseChapters(response.doc);
      const detail = parseDetail(response.doc);
      if (chapters[0] && detail.updateTime) chapters[0].date = detail.updateTime;
      return mx.report("[Roumanwu] chapters", {
        url: response.finalUrl,
        status: response.status,
        count: chapters.length,
        sample: mx.sample(chapters),
      });
    },

    async pages(chapterPath) {
      const path = normalizeChapterPath(chapterPath);
      const response = await mx.request(`${base}${path}`, {
        headers: { rsc: "1" },
      });
      const pages = parsePagesFromHtml(response.text);
      return mx.report("[Roumanwu] pages", {
        url: response.finalUrl,
        status: response.status,
        chapterPath: path,
        count: pages.length,
        sample: mx.sample(pages),
      });
    },
  };
})();
```

先测：

```js
await MXRoumanwu.popular();
await MXRoumanwu.latest();
```

补充：

```js
await MXRoumanwu.search("老师", 1);
await MXRoumanwu.browse(1, "");
await MXRoumanwu.browse(1, "true");
await MXRoumanwu.detail("/books/your-slug");
await MXRoumanwu.chapters("/books/your-slug");
await MXRoumanwu.pages("/books/your-slug/0");
```

## NoyAcg

说明：

- NoyAcg 必须先登录，后续热门、最新、搜索、详情、章节、页面链路才能稳定返回数据。
- 不要把真实账号密码写进脚本文件，直接在控制台调用时把账号密码作为参数传入。
- 建议先打开 `https://noy1.top/#/login` 或 `https://noy1.top/#/index`，确认当前域名就是 `noy1.top`。

```js
window.MXNoyAcg = (() => {
  const mx = window.MX;
  const base = location.origin;
  const cdnOptions = [
    "https://img.noy.asia",
    "https://img.noyteam.online",
    "https://img.457475.xyz",
  ];

  const normalizeId = (value) => {
    const match = String(value ?? "").match(/(\d+)/);
    return match ? match[1] : "";
  };

  const formatTime = (value) => {
    const unix = Number(value || 0);
    if (!unix) return "";
    return new Date(unix * 1000).toISOString().replace("T", " ").slice(0, 19);
  };

  const cleanTags = (value) =>
    String(value || "")
      .replace(/\s+/g, ", ")
      .replace(/,+/g, ", ")
      .replace(/^, |, $/g, "");

  const joinGenre = (item) =>
    [cleanTags(item.Ptag), String(item.Otag || "")]
      .filter(Boolean)
      .join(", ");

  const buildDescription = (item) =>
    [
      `时间：${formatTime(item.Time)}`,
      `页数：${String(item.Len || 0)}`,
      `原作：${String(item.Otag || "")}`,
      `角色：${String(item.Pname || "")}`,
    ].join("\n");

  const ensureOk = (response, apiName) => {
    if (!response.ok) {
      throw new Error(`[NoyAcg] ${apiName} 请求失败: HTTP ${response.status}`);
    }
    if (response.parseError) {
      throw new Error(`[NoyAcg] ${apiName} JSON 解析失败: ${response.parseError}`);
    }
  };

  const ensureLogin = (data, apiName) => {
    if (data?.status === "login" || (Array.isArray(data) && data[0] === "login")) {
      throw new Error(`[NoyAcg] ${apiName} 返回登录失效，请先重新登录`);
    }
  };

  const postApi = async (path, data = {}) => {
    const response = await mx.postForm(`${base}${path}`, data);
    ensureOk(response, path);
    return response.json;
  };

  const mapItem = (item, imageCdn) => ({
    id: String(item.Bid || ""),
    path: `#/book/${String(item.Bid || "")}`,
    title: String(item.Bookname || ""),
    author: String(item.Author || ""),
    cover: `${imageCdn}/${String(item.Bid || "")}/m1.webp`,
    genre: joinGenre(item),
    description: buildDescription(item),
  });

  return {
    cdnOptions,

    async login(username, password) {
      const user = String(username ?? "").trim();
      const pass = String(password ?? "").trim();
      if (!user || !pass) {
        throw new Error("[NoyAcg] login 缺少账号或密码");
      }
      const response = await mx.postForm(`${base}/api/login`, { user, pass });
      ensureOk(response, "/api/login");
      if (response.json?.status !== "ok") {
        throw new Error(`[NoyAcg] 登录失败: ${JSON.stringify(response.json)}`);
      }
      return mx.report("[NoyAcg] login", {
        status: response.json.status,
        session: response.json.SESSION || "",
        cookieVisible: document.cookie.includes("NOY_SESSION"),
      });
    },

    async popular(page = 1, imageCdn = cdnOptions[0]) {
      const data = await postApi("/api/readLeaderboard", { page, type: "day" });
      ensureLogin(data, "/api/readLeaderboard");
      const list = Array.isArray(data.info) ? data.info : [];
      const mangas = list.map((item) => mapItem(item, imageCdn));
      return mx.report("[NoyAcg] popular", {
        page,
        imageCdn,
        total: Number(data.len || 0),
        count: mangas.length,
        hasNextPage: Number(page) * 20 < Number(data.len || 0),
        sample: mx.sample(mangas),
      });
    },

    async latest(page = 1, imageCdn = cdnOptions[0]) {
      const data = await postApi("/api/booklist_v2", { page });
      ensureLogin(data, "/api/booklist_v2");
      const list = Array.isArray(data.info) ? data.info : [];
      const mangas = list.map((item) => mapItem(item, imageCdn));
      return mx.report("[NoyAcg] latest", {
        page,
        imageCdn,
        total: Number(data.len || 0),
        count: mangas.length,
        hasNextPage: Number(page) * 20 < Number(data.len || 0),
        sample: mx.sample(mangas),
      });
    },

    async search(query, page = 1, imageCdn = cdnOptions[0]) {
      const data = await postApi("/api/search_v2", {
        page,
        info: String(query ?? "").trim(),
        type: "de",
        sort: "bid",
      });
      ensureLogin(data, "/api/search_v2[type=de]");
      const list = Array.isArray(data.info) ? data.info : [];
      const mangas = list.map((item) => mapItem(item, imageCdn));
      return mx.report("[NoyAcg] search", {
        query,
        page,
        imageCdn,
        total: Number(data.len || 0),
        count: mangas.length,
        sample: mx.sample(mangas),
      });
    },

    async searchByTag(tag, page = 1, imageCdn = cdnOptions[0]) {
      const data = await postApi("/api/search_v2", {
        page,
        info: String(tag ?? "").trim(),
        type: "tag",
        sort: "bid",
      });
      ensureLogin(data, "/api/search_v2[type=tag]");
      const list = Array.isArray(data.info) ? data.info : [];
      const mangas = list.map((item) => mapItem(item, imageCdn));
      return mx.report("[NoyAcg] searchByTag", {
        tag,
        page,
        imageCdn,
        total: Number(data.len || 0),
        count: mangas.length,
        sample: mx.sample(mangas),
      });
    },

    async searchByAuthor(author, page = 1, imageCdn = cdnOptions[0]) {
      const data = await postApi("/api/search_v2", {
        page,
        info: String(author ?? "").trim(),
        type: "author",
        sort: "bid",
      });
      ensureLogin(data, "/api/search_v2[type=author]");
      const list = Array.isArray(data.info) ? data.info : [];
      const mangas = list.map((item) => mapItem(item, imageCdn));
      return mx.report("[NoyAcg] searchByAuthor", {
        author,
        page,
        imageCdn,
        total: Number(data.len || 0),
        count: mangas.length,
        sample: mx.sample(mangas),
      });
    },

    async searchById(query, imageCdn = cdnOptions[0]) {
      const bid = normalizeId(query);
      if (!bid) {
        throw new Error("[NoyAcg] searchById 无法提取作品 ID");
      }
      const detail = await this.detail(bid, imageCdn);
      return mx.report("[NoyAcg] searchById", {
        query,
        id: bid,
        detail: detail.detail,
      });
    },

    async detail(mangaId, imageCdn = cdnOptions[0]) {
      const bid = normalizeId(mangaId);
      if (!bid) {
        throw new Error("[NoyAcg] detail 缺少作品 ID");
      }
      const item = await postApi("/api/getbookinfo", { bid });
      ensureLogin(item, "/api/getbookinfo");
      const detail = {
        id: bid,
        path: `#/book/${bid}`,
        title: String(item.Bookname || ""),
        author: String(item.Author || ""),
        cover: `${imageCdn}/${bid}/m1.webp`,
        genre: joinGenre(item),
        description: buildDescription(item),
        status: "completed",
        pageCount: Math.max(0, Number(item.Len || 0)),
      };
      return mx.report("[NoyAcg] detail", {
        id: bid,
        imageCdn,
        detail,
      });
    },

    async chapters(mangaId) {
      const bid = normalizeId(mangaId);
      if (!bid) {
        throw new Error("[NoyAcg] chapters 缺少作品 ID");
      }
      const item = await postApi("/api/getbookinfo", { bid });
      ensureLogin(item, "/api/getbookinfo");
      const pageCount = Math.max(0, Number(item.Len || 0));
      const chapters = [
        {
          id: `${bid}#${pageCount}`,
          path: `#/read/${bid}`,
          title: "单话",
          publishTime: formatTime(item.Time),
          size: pageCount,
        },
      ];
      return mx.report("[NoyAcg] chapters", {
        id: bid,
        count: chapters.length,
        chapters,
      });
    },

    async pages(chapterId, imageCdn = cdnOptions[0]) {
      const raw = String(chapterId ?? "").trim();
      let bid = "";
      let pageCount = 0;
      if (raw.includes("#")) {
        const parts = raw.split("#");
        bid = normalizeId(parts[0]);
        pageCount = Math.max(0, parseInt(parts[1], 10) || 0);
      } else {
        bid = normalizeId(raw);
      }
      if (!bid) {
        throw new Error("[NoyAcg] pages 缺少章节 ID");
      }
      if (!pageCount) {
        const item = await postApi("/api/getbookinfo", { bid });
        ensureLogin(item, "/api/getbookinfo");
        pageCount = Math.max(0, Number(item.Len || 0));
      }
      const pages = Array.from({ length: pageCount }, (_, index) => ({
        index: index + 1,
        url: `${imageCdn}/${bid}/${index + 1}.webp`,
      }));
      return mx.report("[NoyAcg] pages", {
        chapterId: raw || bid,
        imageCdn,
        count: pages.length,
        sample: mx.sample(pages),
      });
    },

    async verify(username, password, options = {}) {
      const imageCdn = options.imageCdn ?? cdnOptions[0];
      const searchQuery = options.searchQuery ?? "鲨";
      const tagQuery = options.tagQuery ?? "人妻";
      const authorQuery = options.authorQuery ?? "LDZ";
      const idQuery = options.idQuery ?? "60704";

      const login = await this.login(username, password);
      const popular = await this.popular(1, imageCdn);
      const latest = await this.latest(1, imageCdn);
      const search = await this.search(searchQuery, 1, imageCdn);
      const tag = await this.searchByTag(tagQuery, 1, imageCdn);
      const author = await this.searchByAuthor(authorQuery, 1, imageCdn);
      const byId = await this.searchById(idQuery, imageCdn);

      const targetId =
        normalizeId(options.detailId) ||
        normalizeId(byId.detail?.id) ||
        normalizeId(popular.sample?.[0]?.id) ||
        idQuery;

      const detail = await this.detail(targetId, imageCdn);
      const chapters = await this.chapters(targetId);
      const firstChapterId =
        chapters.chapters?.[0]?.id || `${targetId}#${detail.detail?.pageCount || 0}`;
      const pages = await this.pages(firstChapterId, imageCdn);

      return mx.report("[NoyAcg] verify", {
        loginStatus: login.status,
        popularCount: popular.count,
        latestCount: latest.count,
        searchCount: search.count,
        tagCount: tag.count,
        authorCount: author.count,
        detailTitle: detail.detail?.title || "",
        chapterCount: chapters.count,
        pageCount: pages.count,
        byIdTitle: byId.detail?.title || "",
        sampleChapter: chapters.chapters?.[0] || null,
      });
    },
  };
})();
```

先测：

```js
await MXNoyAcg.verify("你的账号", "你的密码");
```

补充：

```js
await MXNoyAcg.login("你的账号", "你的密码");
await MXNoyAcg.popular(1);
await MXNoyAcg.latest(1);
await MXNoyAcg.search("鲨", 1);
await MXNoyAcg.searchByTag("人妻", 1);
await MXNoyAcg.searchByAuthor("LDZ", 1);
await MXNoyAcg.searchById("60704");
await MXNoyAcg.detail("60704");
await MXNoyAcg.chapters("60704");
await MXNoyAcg.pages("60704#51");
```

## 建议你优先回传的结果

```js
await MXPhotos18.latest(1);
await MXEveria.popular(1);
await MXWNACG.popular(1);
await MXWNACG.search("FGO", 1);
await MXManwa.popular();
await MXManwa.latest(1);
await MXRoumanwu.popular();
await MXRoumanwu.latest();
await MXNoyAcg.verify("你的账号", "你的密码");
```

然后补这些关键链路：

```js
await MXWNACG.detail("/photos-index-aid-123456.html");
await MXWNACG.pages("/photos-index-aid-123456.html");
await MXManwa.detail("159321");
await MXManwa.chapters("159321");
await MXManwa.pages("/chapter/30284528");
await MXRoumanwu.detail("/books/your-slug");
await MXRoumanwu.chapters("/books/your-slug");
await MXRoumanwu.pages("/books/your-slug/0");
await MXNoyAcg.searchById("60704");
await MXNoyAcg.detail("60704");
await MXNoyAcg.chapters("60704");
await MXNoyAcg.pages("60704#51");
```
