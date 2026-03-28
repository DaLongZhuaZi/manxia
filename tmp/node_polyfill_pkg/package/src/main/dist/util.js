import require$$2 from '@ohos.util';
import { p as primordials } from './primordials-4u6fpP8i.js';
import { v as validator } from './validator-4OkgCN7J.js';
import require$$0 from '@ohos.process';
import require$$1 from '@ohos.hilog';
import { b as buffer } from './index-t9dAgl11.js';
import './_commonjsHelpers-YxXKG0rd.js';

var util$2 = {};

const process = require$$0;
const hilog = require$$1;
const util$1 = require$$2;
const {
  ObjectCreate,
  ObjectDefineProperty: ObjectDefineProperty$1,
  StringPrototypeToUpperCase,
  ArrayPrototypeSlice,
} = primordials;

let debugImpls = ObjectCreate(null);

const noop = () => {};

function debuglogImpl(enabled, set) {
  if (debugImpls[set] === undefined) {
    if (enabled) {
      const pid = process.pid;
      debugImpls[set] = function debug(format, ...args) {
        var msg = util$1.printf(format, ...args);
        hilog.debug(
          pid,
          set,
          "%{public}s %{public}s: %{public}s",
          set,
          pid,
          msg
        );
      };
    } else {
      debugImpls[set] = noop;
    }
  }
  return debugImpls[set];
}

function debuglog$1(set, cb) {
  function init() {
    set = StringPrototypeToUpperCase(set);
    enabled = true;
  }

  let debug = (...args) => {
    init();
    debug = debuglogImpl(enabled, set);
    if (typeof cb === "function") {
      cb(debug);
    }
    switch (args.length) {
      case 1:
        return debug(args[0]);
      case 2:
        return debug(args[0], args[1]);
      default:
        return debug(args[0], ...ArrayPrototypeSlice(args, 1));
    }
  };
  let enabled;
  let test = () => {
    init();
    test = () => enabled;
    return enabled;
  };
  const logger = (...args) => {
    switch (args.length) {
      case 1:
        return debug(args[0]);
      case 2:
        return debug(args[0], args[1]);
      default:
        return debug(args[0], ...ArrayPrototypeSlice(args, 1));
    }
  };
  ObjectDefineProperty$1(logger, "enabled", {
    __proto__: null,
    get() {
      return test();
    },
    configurable: true,
    enumerable: true,
  });
  return logger;
}

var debuglog_1$1 = {
  debuglog: debuglog$1,
};

var pSlice = Array.prototype.slice;
var Object_keys = typeof Object.keys === 'function'
    ? Object.keys
    : function (obj) {
        var keys = [];
        for (var key in obj) keys.push(key);
        return keys;
    }
;

function deepEqual(actual, expected) {
    if (actual === 0 && expected === 0) {
        return areZerosEqual(actual, expected);
    } else if (actual === expected) {
        return true;
    } else if (actual instanceof Date && expected instanceof Date) {
        try{
            return actual.getTime() === expected.getTime();
        } catch (e) {
            return false;
        }
    } else if (isNumberNaN(actual)) {
        return isNumberNaN(expected);
    } else if (typeof actual != 'object' && typeof expected != 'object') {
        return actual === expected;
    } else if (isBoxedPrimitive(actual) || isBoxedPrimitive(expected)) {
        return isEqualBoxedPrimitive(actual, expected);
    } else {
        return objEquiv(actual, expected);
    }
}
function isUndefinedOrNull(value) {
    return value === null || value === undefined;
}

function isArgumentsObject(object) {
    return Object.prototype.toString.call(object) == '[object Arguments]';
}

function isNumberObject(object) {
    return Object.prototype.toString.call(object) == '[object Number]';
}

function isStringObject(object) {
    return Object.prototype.toString.call(object) == '[object String]';
}

function isBooleanObject(object) {
    return Object.prototype.toString.call(object) == '[object Boolean]';
}

function isBigIntObject(object) {
    return Object.prototype.toString.call(object) == '[object BigInt]';
}

function isSymbolObject(object) {
    return Object.prototype.toString.call(object) == '[object Symbol]';
}

function isBoxedPrimitive(object) {
    return object === null ||
    typeof object === 'boolean' ||
    typeof object === 'number' ||
    typeof object === 'string' ||
    typeof object === 'symbol' ||  // ES6 symbol
    typeof object === 'undefined';
}


function isEqualBoxedPrimitive(val1, val2) {
    if (!isBoxedPrimitive(val1) || !isBoxedPrimitive(val2)) {
        return false;
    }

    if (isNumberObject(val1)) {
        return isNumberObject(val2) && ObjectIs(val1.valueOf(), val2.valueOf());
    }
    if (isStringObject(val1)) {
        return isStringObject(val2) && val1.valueOf() === val2.valueOf();
    }
    if (isBooleanObject(val1)) {
        return isBooleanObject(val2) && val1.valueOf() === val2.valueOf();
    }
    if (isBigIntObject(val1)) {
        return isBigIntObject(val2) && val1.valueOf() === val2.valueOf();
    }
    if (isSymbolObject(val1)) {
        return isSymbolObject(val2) && Object(val1).toString() === Object(val2).toString();
    }
    return objEquiv(val1, val2);
}

function ObjectIs(x, y) {
    if (x === y) {
        // 针对+0 不等于 -0的情况
        return x !== 0 || 1 / x === 1 / y;
    } else {
        // 针对NaN的情况
        return x !== x && y !== y;
    }
}

function isNumberNaN(value) {
    // NaN === NaN -> false
    return typeof value == 'number' && value !== value;
}

function areZerosEqual(zeroA, zeroB) {
    // (1 / +0|0) -> Infinity, but (1 / -0) -> -Infinity and (Infinity !== -Infinity)
    return (1 / zeroA) === (1 / zeroB);
}

function objEquiv(a, b) {
    if (isUndefinedOrNull(a) || isUndefinedOrNull(b))
    return false;

    if (a.prototype !== b.prototype) return false;
    if (isArgumentsObject(a)) {
        if (!isArgumentsObject(b)) {
            return false;
        }
        a = pSlice.call(a);
        b = pSlice.call(b);
        return deepEqual(a, b);
    }

    try {
        var ka = Object_keys(a),
            kb = Object_keys(b),
            key, i;
    } catch (e) {
        return false;
    }

    if (ka.length != kb.length)
    return false;

    ka.sort();
    kb.sort();

    for (i = ka.length - 1; i >= 0; i--) {
        if (ka[i] != kb[i])
        return false;
    }

    for (i = ka.length - 1; i >= 0; i--) {
        key = ka[i];
        if (!deepEqual(a[key], b[key])) return false;
    }

    return true;
}

var comparisons = {
    isDeepStrictEqual: deepEqual
};

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

const util = require$$2;

const {
  ArrayIsArray,
  ArrayPrototypeJoin,
  Date: Date$1,
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
} = primordials;

const { validateString } = validator;

const { debuglog } = debuglog_1$1;
const { isDeepStrictEqual } = comparisons;
const { isBuffer } = buffer.Buffer;

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
  const d = new Date$1();
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

util$2.default = {
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

var _extend_1 = util$2._extend = _extend;
var callbackify = util$2.callbackify = callbackWrapper;
var debug = util$2.debug = debuglog;
var debuglog_1 = util$2.debuglog = debuglog;
var format = util$2.format = printf;
var getSystemErrorName = util$2.getSystemErrorName = getErrorString;
var inherits_1 = util$2.inherits = inherits;
var isArray = util$2.isArray = ArrayIsArray;
var isBoolean_1 = util$2.isBoolean = isBoolean;
var isBuffer_1 = util$2.isBuffer = isBuffer;
var isDeepStrictEqual_1 = util$2.isDeepStrictEqual = isDeepStrictEqual;
var isNull_1 = util$2.isNull = isNull;
var isNullOrUndefined_1 = util$2.isNullOrUndefined = isNullOrUndefined;
var isNumber_1 = util$2.isNumber = isNumber;
var isString_1 = util$2.isString = isString;
var isSymbol_1 = util$2.isSymbol = isSymbol;
var isUndefined_1 = util$2.isUndefined = isUndefined;
var isRegExp_1 = util$2.isRegExp = isRegExp;
var isObject_1 = util$2.isObject = isObject;
var isDate_1 = util$2.isDate = isDate;
var isError_1 = util$2.isError = isError;
var isFunction_1 = util$2.isFunction = isFunction;
var isPrimitive_1 = util$2.isPrimitive = isPrimitive;
var log_1 = util$2.log = log;
var promisify = util$2.promisify = promiseWrapper;
var stripVTControlCharacters_1 = util$2.stripVTControlCharacters = stripVTControlCharacters;
var TextDecoder_1 = util$2.TextDecoder = TextDecoder;
var TextEncoder_1 = util$2.TextEncoder = TextEncoder;
var types_1 = util$2.types = types();
var inspect = util$2.inspect = function () {};

export { TextDecoder_1 as TextDecoder, TextEncoder_1 as TextEncoder, _extend_1 as _extend, callbackify, debug, debuglog_1 as debuglog, util$2 as default, format, getSystemErrorName, inherits_1 as inherits, inspect, isArray, isBoolean_1 as isBoolean, isBuffer_1 as isBuffer, isDate_1 as isDate, isDeepStrictEqual_1 as isDeepStrictEqual, isError_1 as isError, isFunction_1 as isFunction, isNull_1 as isNull, isNullOrUndefined_1 as isNullOrUndefined, isNumber_1 as isNumber, isObject_1 as isObject, isPrimitive_1 as isPrimitive, isRegExp_1 as isRegExp, isString_1 as isString, isSymbol_1 as isSymbol, isUndefined_1 as isUndefined, log_1 as log, promisify, stripVTControlCharacters_1 as stripVTControlCharacters, types_1 as types };
