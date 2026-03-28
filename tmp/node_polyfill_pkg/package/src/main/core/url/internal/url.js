"use strict";
const url_oh = require("@ohos.url");

const {
  Number,
  StringPrototypeCharCodeAt,
  StringPrototypeIncludes,
  StringPrototypeReplace,
  StringPrototypeSlice,
  StringPrototypeStartsWith,
  decodeURIComponent,
} = require("../../primordials");

const { validateObject } = require("../../validator");

const { encodeStr } = require("../../querystring/internal/querystring");

const { CHAR_BACKWARD_SLASH, CHAR_FORWARD_SLASH } = require("../../constants");
const path = require("../../path");

const URLSearchParams = url_oh.URLSearchParams;

const { encode, decode } = require("./punycode");

const kFormat = Symbol("format");

class URL extends url_oh.URL {
  constructor(input, base = undefined) {
    if (base == undefined || base == null) {
      super(input);
    } else {
      super(input, base);
    }
  }

  [kFormat](options) {
    if (options) validateObject(options, "options");

    options = {
      fragment: true,
      unicode: false,
      search: true,
      auth: true,
      ...options,
    };

    // https://url.spec.whatwg.org/#url-serializing
    let ret = this.protocol;
    if (this.host !== null) {
      this.host = domainToASCII(decodeURI(this.host));
      ret += "//";
      const has_username = this.username !== "";
      const has_password = this.password !== "";
      if (options.auth && (has_username || has_password)) {
        if (has_username) ret += this.username;
        if (has_password) ret += `:${this.password}`;
        ret += "@";
      }
      ret += options.unicode ? domainToUnicode(this.host) : this.host;
      if (this.port !== null && this.port.length > 0) ret += `:${this.port}`;
    }

    ret += this.pathname;

    if (options.search && this.search !== null && this.search.length > 0)
      ret += `${this.search}`;
    if (options.fragment && this.hash !== null && this.hash.length > 0)
      ret += `${this.hash}`;
    return ret;
  }

  static createObjectURL(obj) {
    //待实现
  }

  static revokeObjectURL(url) {
    //待实现
  }
}

function domainToASCII(domain) {
  if (typeof domain !== "string") {
    return "";
  }
  if (
    domain.startsWith("xn--") ||
    domain.includes(":") ||
    domain.includes("//")
  ) {
    return "";
  }
  try {
    var domainArray = domain.split(".");
    var out = [];
    for (var i = 0; i < domainArray.length; ++i) {
      var s = domainArray[i];
      out.push(s.match(/[^A-Za-z0-9-]/) ? "xn--" + encode(s) : s);
    }
    return out.join(".");
  } catch (err) {
    return "";
  }
}

function domainToUnicode(domain) {
  try {
    var domainArray = domain.split(".");
    var out = [];
    for (var i = 0; i < domainArray.length; ++i) {
      var s = domainArray[i];
      out.push(s.match(/^xn--/) ? decode(s.slice(4)) : s);
    }
    return out.join(".");
  } catch (err) {
    return "";
  }
}

// Utility function that converts a URL object into an ordinary
// options object as expected by the http.request and https.request
// APIs.
function urlToHttpOptions(url) {
  const options = {
    protocol: url.protocol,
    hostname:
      typeof url.hostname === "string" &&
      StringPrototypeStartsWith(url.hostname, "[")
        ? StringPrototypeSlice(url.hostname, 1, -1)
        : url.hostname,
    hash: url.hash,
    search: url.search,
    pathname: url.pathname,
    path: `${url.pathname || ""}${url.search || ""}`,
    href: url.href,
  };
  if (url.port !== "") {
    options.port = Number(url.port);
  }
  if (url.username || url.password) {
    options.auth = `${decodeURIComponent(url.username)}:${decodeURIComponent(
      url.password
    )}`;
  }
  return options;
}

function getPathFromURLPosix(url) {
  if (url.hostname !== "") {
    throw new Error("");
  }
  const pathname = url.pathname;
  for (let n = 0; n < pathname.length; n++) {
    if (pathname[n] === "%") {
      const third = pathname.codePointAt(n + 2) | 0x20;
      if (pathname[n + 1] === "2" && third === 102) {
        throw new Error("must not include encoded / characters");
      }
    }
  }
  return decodeURIComponent(pathname);
}

function fileURLToPath(path) {
  if (typeof path === "string") path = new URL(path);
  else if (!isURLInstance(path))
    throw new Error("ERR_INVALID_ARG_TYPE, path:" + path);
  if (path.protocol !== "file:")
    throw new Error("ERR_INVALID_URL_SCHEME, file");
  return getPathFromURLPosix(path);
}

// The following characters are percent-encoded when converting from file path
// to URL:
// - %: The percent character is the only character not encoded by the
//        `pathname` setter.
// - \: Backslash is encoded on non-windows platforms since it's a valid
//      character but the `pathname` setters replaces it by a forward slash.
// - LF: The newline character is stripped out by the `pathname` setter.
//       (See whatwg/url#419)
// - CR: The carriage return character is also stripped out by the `pathname`
//       setter.
// - TAB: The tab character is also stripped out by the `pathname` setter.
const percentRegEx = /%/g;
const backslashRegEx = /\\/g;
const newlineRegEx = /\n/g;
const carriageReturnRegEx = /\r/g;
const tabRegEx = /\t/g;
const hashRegEx = /#/g;

function encodePathChars(filepath) {
  //    if (StringPrototypeIncludes(filepath, '%'))
  //    filepath = StringPrototypeReplace(filepath, percentRegEx, '%25');
  if (StringPrototypeIncludes(filepath, "#"))
    filepath = StringPrototypeReplace(filepath, hashRegEx, "%23");
  // In posix, backslash is a valid character in paths:
  if (StringPrototypeIncludes(filepath, "\\"))
    filepath = StringPrototypeReplace(filepath, backslashRegEx, "%5C");
  if (StringPrototypeIncludes(filepath, "\n"))
    filepath = StringPrototypeReplace(filepath, newlineRegEx, "%0A");
  if (StringPrototypeIncludes(filepath, "\r"))
    filepath = StringPrototypeReplace(filepath, carriageReturnRegEx, "%0D");
  if (StringPrototypeIncludes(filepath, "\t"))
    filepath = StringPrototypeReplace(filepath, tabRegEx, "%09");
  return filepath;
}

function pathToFileURL(filepath) {
  const outURL = new URL("file://");
  let resolved = path.resolve(filepath);
  const filePathLast = StringPrototypeCharCodeAt(filepath, filepath.length - 1);
  if (
    (filePathLast === CHAR_FORWARD_SLASH ||
      filePathLast === CHAR_BACKWARD_SLASH) &&
    resolved[resolved.length - 1] !== path.sep
  )
    resolved += "/";
  outURL.pathname = encodePathChars(resolved);
  return outURL;
}

function isURLInstance(fileURLOrPath) {
  return fileURLOrPath != null && fileURLOrPath.href && fileURLOrPath.origin;
}

function toPathIfFileURL(fileURLOrPath) {
  if (!isURLInstance(fileURLOrPath)) return fileURLOrPath;
  return fileURLToPath(fileURLOrPath);
}

module.exports = {
  fileURLToPath,
  pathToFileURL,
  toPathIfFileURL,
  isURLInstance,
  URL,
  URLSearchParams,
  domainToASCII,
  domainToUnicode,
  urlToHttpOptions,
  formatSymbol: kFormat,
  encodeStr,
};
