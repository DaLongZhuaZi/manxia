import { RequestHeaderEntry, RequestHeaders } from '../Cache/ImageCacheManager';

/**
 * Keeps page-level image headers in the typed transport fields that the image
 * loader consumes. Unknown headers remain available as explicit extensions.
 */
export class MangaRequestHeaderContract {
  public static clone(headers: RequestHeaders | undefined): RequestHeaders {
    const cloned: RequestHeaders = {} as RequestHeaders;
    if (!headers) {
      return cloned;
    }
    cloned.userAgent = headers.userAgent;
    cloned.accept = headers.accept;
    cloned.referer = headers.referer;
    cloned.origin = headers.origin;
    cloned.cookie = headers.cookie;
    cloned.authorization = headers.authorization;
    cloned.acceptLanguage = headers.acceptLanguage;
    cloned.cacheControl = headers.cacheControl;
    cloned.pragma = headers.pragma;
    cloned.secFetchDest = headers.secFetchDest;
    cloned.secFetchMode = headers.secFetchMode;
    cloned.secFetchSite = headers.secFetchSite;
    cloned.cachePartition = headers.cachePartition;
    if (headers.extraHeaders && headers.extraHeaders.length > 0) {
      cloned.extraHeaders = [];
      for (let index = 0; index < headers.extraHeaders.length; index++) {
        const entry: RequestHeaderEntry = headers.extraHeaders[index];
        if (entry && entry.name && entry.value) {
          cloned.extraHeaders.push({
            name: entry.name,
            value: entry.value
          } as RequestHeaderEntry);
        }
      }
    }
    return cloned;
  }

  public static apply(target: RequestHeaders, headerName: string, headerValue: string): void {
    const normalizedName: string = headerName.trim();
    const normalizedValue: string = headerValue.trim();
    if (normalizedName.length === 0 || normalizedValue.length === 0) {
      return;
    }

    const standardKey: string = MangaRequestHeaderContract.resolveStandardKey(normalizedName);
    if (standardKey.length === 0) {
      MangaRequestHeaderContract.upsertExtra(target, normalizedName, normalizedValue);
      return;
    }

    MangaRequestHeaderContract.assignStandard(target, standardKey, normalizedValue);
    MangaRequestHeaderContract.removeEquivalentExtras(target, standardKey);
  }

  private static resolveStandardKey(headerName: string): string {
    switch (headerName.trim().toLowerCase()) {
      case 'user-agent':
      case 'useragent':
        return 'userAgent';
      case 'accept':
        return 'accept';
      case 'referer':
        return 'referer';
      case 'origin':
        return 'origin';
      case 'cookie':
        return 'cookie';
      case 'authorization':
        return 'authorization';
      case 'accept-language':
      case 'acceptlanguage':
        return 'acceptLanguage';
      case 'cache-control':
      case 'cachecontrol':
        return 'cacheControl';
      case 'pragma':
        return 'pragma';
      case 'sec-fetch-dest':
      case 'secfetchdest':
        return 'secFetchDest';
      case 'sec-fetch-mode':
      case 'secfetchmode':
        return 'secFetchMode';
      case 'sec-fetch-site':
      case 'secfetchsite':
        return 'secFetchSite';
      case 'cache-partition':
      case 'cachepartition':
        return 'cachePartition';
      default:
        return '';
    }
  }

  private static assignStandard(target: RequestHeaders, standardKey: string, value: string): void {
    switch (standardKey) {
      case 'userAgent':
        target.userAgent = value;
        return;
      case 'accept':
        target.accept = value;
        return;
      case 'referer':
        target.referer = value;
        return;
      case 'origin':
        target.origin = value;
        return;
      case 'cookie':
        target.cookie = value;
        return;
      case 'authorization':
        target.authorization = value;
        return;
      case 'acceptLanguage':
        target.acceptLanguage = value;
        return;
      case 'cacheControl':
        target.cacheControl = value;
        return;
      case 'pragma':
        target.pragma = value;
        return;
      case 'secFetchDest':
        target.secFetchDest = value;
        return;
      case 'secFetchMode':
        target.secFetchMode = value;
        return;
      case 'secFetchSite':
        target.secFetchSite = value;
        return;
      case 'cachePartition':
        target.cachePartition = value;
        return;
      default:
        return;
    }
  }

  private static removeEquivalentExtras(target: RequestHeaders, standardKey: string): void {
    if (!target.extraHeaders || target.extraHeaders.length === 0) {
      return;
    }
    const retained: RequestHeaderEntry[] = [];
    for (let index = 0; index < target.extraHeaders.length; index++) {
      const entry: RequestHeaderEntry = target.extraHeaders[index];
      if (!entry || !entry.name || !entry.value) {
        continue;
      }
      if (MangaRequestHeaderContract.resolveStandardKey(entry.name) !== standardKey) {
        retained.push({
          name: entry.name,
          value: entry.value
        } as RequestHeaderEntry);
      }
    }
    target.extraHeaders = retained.length > 0 ? retained : undefined;
  }

  private static upsertExtra(target: RequestHeaders, headerName: string, headerValue: string): void {
    if (!target.extraHeaders) {
      target.extraHeaders = [];
    }
    for (let index = 0; index < target.extraHeaders.length; index++) {
      const entry: RequestHeaderEntry = target.extraHeaders[index];
      if (entry.name.toLowerCase() === headerName.toLowerCase()) {
        entry.value = headerValue;
        return;
      }
    }
    target.extraHeaders.push({
      name: headerName,
      value: headerValue
    } as RequestHeaderEntry);
  }
}
