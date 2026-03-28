// Copyright Joyent, Inc. and other Node contributors.
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to permit
// persons to whom the Software is furnished to do so, subject to the
// following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
// NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
// OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
// USE OR OTHER DEALINGS IN THE SOFTWARE.

const util = require("@ohos.util");

const {
  ArrayIsArray,
  ArrayPrototypeJoin,
  Date,
  DatePrototypeGetDate,
  DatePrototypeGetHours,
  DatePrototypeGetMinutes,
  DatePrototypeGetMonth,
  DatePrototypeGetSeconds,
  Error,
  ObjectDefineProperty,
  ObjectKeys,
  ObjectPrototypeToString,
  ObjectSetPrototypeOf,
  StringPrototypePadStart,
} = require("../primordials");

const { validateString } = require("../validator");

const { debuglog } = require("./internal/debuglog");
const { isDeepStrictEqual } = require("./internal/comparisons");
const { isBuffer } = require("../buffer").Buffer;

/**
 * @param {any} arg
 * @returns {arg is boolean}
 */
function isBoolean(arg) {
  return typeof arg === "boolean";
}

/**
 * @param {any} arg
 * @returns {arg is null}
 */
function isNull(arg) {
  return arg === null;
}

/**
 * @param {any} arg
 * @returns {arg is (null | undefined)}
 */
function isNullOrUndefined(arg) {
  return arg === null || arg === undefined;
}

/**
 * @param {any} arg
 * @returns {arg is number}
 */
function isNumber(arg) {
  return typeof arg === "number";
}

/**
 * @param {any} arg
 * @returns {arg is string}
 */
function isString(arg) {
  return typeof arg === "string";
}

/**
 * @param {any} arg
 * @returns {arg is symbol}
 */
function isSymbol(arg) {
  return typeof arg === "symbol";
}

/**
 * @param {any} arg
 * @returns {arg is undefined}
 */
function isUndefined(arg) {
  return arg === undefined;
}

/**
 * @param {any} arg
 * @returns {a is NonNullable<object>}
 */
function isObject(arg) {
  return arg !== null && typeof arg === "object";
}

/**
 * @param {any} e
 * @returns {arg is Error}
 */
function isError(e) {
  return ObjectPrototypeToString(e) === "[object Error]" || e instanceof Error;
}

/**
 * @param {any} arg
 * @returns {arg is Function}
 */
function isFunction(arg) {
  return typeof arg === "function";
}

/**
 * @param {any} arg
 * @returns {arg is (boolean | null | number | string | symbol | undefined)}
 */
function isPrimitive(arg) {
  return arg === null || (typeof arg !== "object" && typeof arg !== "function");
}

/**
 * @param {number} n
 * @returns {string}
 */
function pad(n) {
  return StringPrototypePadStart(n.toString(), 2, "0");
}

const months = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];

/**
 * @returns {string}  26 Feb 16:19:34
 */
function timestamp() {
  const d = new Date();
  const t = ArrayPrototypeJoin(
    [
      pad(DatePrototypeGetHours(d)),
      pad(DatePrototypeGetMinutes(d)),
      pad(DatePrototypeGetSeconds(d)),
    ],
    ":"
  );
  return `${DatePrototypeGetDate(d)} ${months[DatePrototypeGetMonth(d)]} ${t}`;
}

/**
 * Log is just a thin wrapper to console.log that prepends a timestamp
 * @type {(...args: any[]) => void}
 */
function log(...args) {
  console.log("%s - %s", timestamp(), ...args);
}

/**
 * Inherit the prototype methods from one constructor into another.
 *
 * The Function.prototype.inherits from lang.js rewritten as a standalone
 * function (not on Function.prototype). NOTE: If this file is to be loaded
 * during bootstrapping this function needs to be rewritten using some native
 * functions as prototype setup using normal JavaScript does not work as
 * expected during bootstrapping (see mirror.js in r114903).
 *
 * @param {Function} ctor Constructor function which needs to inherit the
 *     prototype.
 * @param {Function} superCtor Constructor function to inherit prototype from.
 * @throws {TypeError} Will error if either constructor is null, or if
 *     the super constructor lacks a prototype.
 */
function inherits(ctor, superCtor) {
  if (ctor === undefined || ctor === null)
    throw new Error("ERR_INVALID_ARG_TYPE, ctor:" + ctor);

  if (superCtor === undefined || superCtor === null)
    throw new Error("ERR_INVALID_ARG_TYPE, superCtor:" + superCtor);

  if (superCtor.prototype === undefined) {
    throw new Error(
      "ERR_INVALID_ARG_TYPE, superCtor.prototype:" + superCtor.prototype
    );
  }
  ObjectDefineProperty(ctor, "super_", {
    __proto__: null,
    value: superCtor,
    writable: true,
    configurable: true,
  });
  ObjectSetPrototypeOf(ctor.prototype, superCtor.prototype);
}

/**
 * @template T
 * @template S
 * @param {T} target
 * @param {S} source
 * @returns {S extends null ? T : (T & S)}
 */
function _extend(target, source) {
  // Don't do anything if source isn't an object
  if (source === null || typeof source !== "object") return target;

  const keys = ObjectKeys(source);
  let i = keys.length;
  while (i--) {
    target[keys[i]] = source[keys[i]];
  }
  return target;
}

function isRegExp(value) {
  return new util.types().isRegExp(value);
}

function isDate(value) {
  return new util.types().isDate(value);
}

function types() {
  return new util.types();
}

const ansiPattern =
  "[\\u001B\\u009B][[\\]()#;?]*" +
  "(?:(?:(?:(?:;[-a-zA-Z\\d\\/#&.:=?%@~_]+)*" +
  "|[a-zA-Z\\d]+(?:;[-a-zA-Z\\d\\/#&.:=?%@~_]*)*)?\\u0007)" +
  "|(?:(?:\\d{1,4}(?:;\\d{0,4})*)?[\\dA-PR-TZcf-ntqry=><~]))";
const ansi = new RegExp(ansiPattern, "g");

/**
 * Remove all VT control characters. Use to estimate displayed string width.
 */
function stripVTControlCharacters(str) {
  validateString(str, "str");

  return str.replace(ansi, "");
}

const {
  printf,
  getErrorString,
  callbackWrapper,
  promiseWrapper,
  TextDecoder,
  TextEncoder,
} = util;

exports.default = {
  _extend,
  callbackify: callbackWrapper,
  debug: debuglog,
  debuglog,
  format: printf,
  getSystemErrorName: getErrorString,
  inherits,
  isArray: ArrayIsArray,
  isBoolean,
  isBuffer,
  isDeepStrictEqual,
  isNull,
  isNullOrUndefined,
  isNumber,
  isString,
  isSymbol,
  isUndefined,
  isRegExp,
  isObject,
  isDate,
  isError,
  isFunction,
  isPrimitive,
  log,
  promisify: promiseWrapper,
  stripVTControlCharacters,
  TextDecoder,
  TextEncoder,
  types: types(),
  inspect: function () {},
};

exports._extend = _extend;
exports.callbackify = callbackWrapper;
exports.debug = debuglog;
exports.debuglog = debuglog;
exports.format = printf;
exports.getSystemErrorName = getErrorString;
exports.inherits = inherits;
exports.isArray = ArrayIsArray;
exports.isBoolean = isBoolean;
exports.isBuffer = isBuffer;
exports.isDeepStrictEqual = isDeepStrictEqual;
exports.isNull = isNull;
exports.isNullOrUndefined = isNullOrUndefined;
exports.isNumber = isNumber;
exports.isString = isString;
exports.isSymbol = isSymbol;
exports.isUndefined = isUndefined;
exports.isRegExp = isRegExp;
exports.isObject = isObject;
exports.isDate = isDate;
exports.isError = isError;
exports.isFunction = isFunction;
exports.isPrimitive = isPrimitive;
exports.log = log;
exports.promisify = promiseWrapper;
exports.stripVTControlCharacters = stripVTControlCharacters;
exports.TextDecoder = TextDecoder;
exports.TextEncoder = TextEncoder;
exports.types = types();
exports.inspect = function () {};
