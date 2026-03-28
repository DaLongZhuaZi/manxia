/*
 * Copyright (c) 2021 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the 'License');
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an 'AS IS' BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

module.exports = {
  uncurryThis: (function () {
    const { apply, bind, call } = Function.prototype;
    return bind.bind(call);
  })(),

  JSONParse(self) {
    return JSON.parse(self);
  },

 

  /**
   * Math start
   */
  MathAbs(self) {
    return Math.abs(self);
  }, //typeof Math.abs
  MathAcos(self) {
    return Math.acos(self);
  }, // typeof Math.acos
  MathAcosh(self) {
    return Math.acosh(self);
  }, //typeof Math.acosh
  MathAsin(self) {
    return Math.asin(self);
  }, //typeof Math.asin
  MathAsinh(self) {
    return Math.asinh(self);
  }, //typeof Math.asinh
  MathAtan(self) {
    return Math.atan(self);
  }, //typeof Math.atan
  MathAtanh(self) {
    return Math.atanh(self);
  }, //typeof Math.atanh
  MathAtan2(self) {
    return Math.atan2(self);
  }, //typeof Math.atan2
  MathCeil(self) {
    return Math.ceil(self);
  }, //typeof Math.ceil
  MathCbrt(self) {
    return Math.cbrt(self);
  }, //typeof Math.cbrt
  MathExpm1(self) {
    return Math.expm1(self);
  }, //typeof Math.expm1
  MathClz32(self) {
    return Math.clz32(self);
  }, //typeof Math.clz32
  MathCos(self) {
    return Math.cos(self);
  }, //typeof Math.cos
  MathCosh(self) {
    return Math.cosh(self);
  }, //typeof Math.cosh
  MathExp(self) {
    return Math.exp(self);
  }, //typeof Math.exp

  MathFround(self) {
    return Math.fround(self);
  }, //typeof Math.fround
  MathHypot(self) {
    return Math.hypot(self);
  }, //typeof Math.hypot
  MathImul(self) {
    return Math.imul(self);
  }, //typeof Math.imul
  MathLog(self) {
    return Math.log(self);
  }, //typeof Math.log
  MathLog1p(self) {
    return Math.log(self);
  }, //typeof Math.log1p
  MathLog2(self) {
    return Math.log2(self);
  }, //typeof Math.log2
  MathLog10(self) {
    return Math.log10(self);
  }, //typeof Math.log10
  MathMax(...selfs) {
    return Math.max(...selfs);
  }, //typeof Math.max
  MathMaxApply(self) {
    return Math.max.apply(null, self);
  }, //StaticApply<typeof Math.max>
  MathMin(self) {
    return Math.min(self);
  }, //typeof Math.min
  MathPow(self) {
    return Math.pow(self);
  }, //typeof Math.pow
  MathRandom() {
    return Math.random();
  }, //typeof Math.random
  MathRound(self) {
    return Math.round(self);
  }, //typeof Math.round
  MathSign(self) {
    return Math.sign(self);
  }, //typeof Math.sign
  MathSin(self) {
    return Math.sin(self);
  }, //typeof Math.sin
  MathSinh(self) {
    return Math.sinh(self);
  }, //typeof Math.sinh
  MathSqrt(self) {
    return Math.sqrt(self);
  }, //typeof Math.sqrt
  MathTan(self) {
    return Math.tan(self);
  }, //typeof Math.tan
  MathTanh(self) {
    return Math.tanh(self);
  }, //typeof Math.tanh
  MathTrunc(self) {
    return Math.trunc(self);
  }, //typeof Math.trunc
  MathE() {
    return Math.E;
  }, //typeof Math.E
  MathLN10() {
    return Math.LN10;
  }, //typeof Math.LN10
  MathLN2() {
    return Math.LN2;
  }, //typeof Math.LN2
  MathLOG10E() {
    return Math.LOG10E;
  }, //typeof Math.LOG10E
  MathLOG2E() {
    return Math.LOG2E;
  }, //typeof Math.LOG2E
  MathPI() {
    return Math.PI;
  }, //typeof Math.PI
  MathSQRT1_2() {
    return Math.SQRT1_2;
  }, //typeof Math.SQRT1_2
  MathSQRT2() {
    return Math.SQRT2;
  }, //typeof Math.SQRT2

  /**
   * Math end
   */

  /**
   * Reflect start
   */
  ReflectDefineProperty: Reflect.defineProperty, //typeof Reflect.defineProperty
  ReflectDeleteProperty: Reflect.deleteProperty, // typeof Reflect.deleteProperty
  ReflectApply: Reflect.apply,
  ReflectConstruct: Reflect.construct, // typeof Reflect.construct
  ReflectGet: Reflect.get, // typeof Reflect.get
  ReflectGetOwnPropertyDescriptor: Reflect.getOwnPropertyDescriptor, // typeof Reflect.getOwnPropertyDescriptor
  ReflectGetPrototypeOf: Reflect.getPrototypeOf, // typeof Reflect.getPrototypeOf
  ReflectHas: Reflect.has, // typeof Reflect.has
  ReflectIsExtensible: Reflect.isExtensible, // typeof Reflect.isExtensible
  ReflectOwnKeys: Reflect.ownKeys, // typeof Reflect.ownKeys
  ReflectPreventExtensions: Reflect.preventExtensions, // typeof Reflect.preventExtensions
  ReflectSet: Reflect.set, //typeof Reflect.set
  ReflectSetPrototypeOf: Reflect.setPrototypeOf, // typeof Reflect.setPrototypeOf
  /**
   * Reflect end
   */

  AggregateError: require("./AggregateError"),

  /**
   * Array start
   */
  ArrayFrom(self, fn) {
    return Array.from(self, fn);
  },

  ArrayIsArray(self) {
    return Array.isArray(self);
  },

  ArrayPrototypeIncludes(self, el) {
    return self.includes(el);
  },

  ArrayPrototypeFilter(self, fn) {
    return self.filter(fn);
  },

  ArrayPrototypeIndexOf(self, el) {
    return self.indexOf(el);
  },

  ArrayPrototypeJoin(self, sep) {
    return self.join(sep);
  },

  ArrayPrototypeMap(self, fn) {
    return self.map(fn);
  },

  ArrayPrototypePop(self, el) {
    return self.pop(el);
  },

  ArrayPrototypePush(self, el) {
    return self.push(el);
  },

  ArrayPrototypeSlice(self, start, end) {
    return self.slice(start, end);
  },

  ArrayPrototypeSplice(self, start, end, ...args) {
    return self.splice(start, end, ...args);
  },

  ArrayPrototypeUnshift(self, value) {
    return self.unshift(value);
  },

  /**
   * Array end
   */

  /**
   * Map start
   */

  MapPrototypeGet: Map.prototype.get,
  /**
   * Map end
   */
  /**
   * Error start
   */
  Error,
  ErrorCaptureStackTrace: Error.captureStackTrace,
  ErrorPrototypeToString: Error.prototype.toString,
  RangeError,
  /**
   * Error end
   */

  /**
   * JSON start
   */
  JSONStringify: JSON.stringify,

  /**
   * JSON end
   */
  FunctionPrototypeCall(fn, thisArgs, ...args) {
    return fn.call(thisArgs, ...args);
  },

  FunctionPrototypeBind(fn, thisArgs, ...args) {
    return fn.bind(thisArgs, ...args);
  },

  FunctionPrototypeSymbolHasInstance(self, instance) {
    return Function.prototype[Symbol.hasInstance].call(self, instance);
  },

  MathFloor: Math.floor,
  Number,
  NumberIsInteger: Number.isInteger,
  NumberIsNaN: Number.isNaN,
  NumberMAX_SAFE_INTEGER: Number.MAX_SAFE_INTEGER,
  NumberMIN_SAFE_INTEGER: Number.MIN_SAFE_INTEGER,
  NumberParseInt: Number.parseInt,
  NumberIsFinite: Number.isFinite,

  NumberPrototypeToString(value, radix) {
    return value.toString(radix);
  },

  /**
   * Object start
   */

  ObjectPrototypeHasOwnProperty(self, name) {
    return Object.prototype.hasOwnProperty.call(self, name);
  },

  ObjectAssign: Object.assign,

  ObjectDefineProperties(self, props) {
    return Object.defineProperties(self, props);
  },

  ObjectDefineProperty(self, name, prop) {
    return Object.defineProperty(self, name, prop);
  },

  ObjectGetOwnPropertyDescriptor(self, name) {
    return Object.getOwnPropertyDescriptor(self, name);
  },

  ObjectKeys(obj) {
    return Object.keys(obj);
  },

  ObjectCreate(obj) {
    return Object.create(obj);
  },

  ObjectFreeze(obj) {
    return Object.freeze(obj);
  },

  ObjectEntries(obj) {
    return Object.entries(obj);
  },

  ObjectSetPrototypeOf(target, proto) {
    return Object.setPrototypeOf(target, proto);
  },

  ObjectPrototypeToString(obj) {
    return obj.toString();
  },

  ObjectPrototypePropertyIsEnumerable(self, val) {
    return self.propertyIsEnumerable(val);
  },

  ObjectIsExtensible: Object.isExtensible,

  /**
   * Object end
   */
  Promise,

  PromisePrototypeCatch(self, fn) {
    return self.catch(fn);
  },

  PromisePrototypeThen(self, thenFn, catchFn) {
    return self.then(thenFn, catchFn);
  },

  PromiseReject(err) {
    return Promise.reject(err);
  },

  RegExpPrototypeTest(self, value) {
    return self.test(value);
  },

  SafeSet: Set,
  String,

  StringPrototypeSlice(self, start, end) {
    return self.slice(start, end);
  },

  StringPrototypeToLowerCase(self) {
    return self.toLowerCase();
  },

  StringPrototypeToUpperCase(self) {
    return self.toUpperCase();
  },

  StringPrototypeTrim(self) {
    return self.trim();
  },

  StringPrototypeCharCodeAt(value, index) {
    return value.charCodeAt(index);
  },

  StringPrototypeLastIndexOf(value, separator) {
    return value.lastIndexOf(separator);
  },

  StringPrototypeCharAt(value, index) {
    return value.charAt(index);
  },

  StringPrototypeIndexOf(value, index) {
    return value.indexOf(index);
  },

  StringPrototypeStartsWith(value, index) {
    return value.startsWith(index);
  },

  StringPrototypeIncludes(self, value, start) {
    return self.includes(value, start);
  },

  StringPrototypePadStart(self, targetLength, padString) {
    return self.padStart(targetLength, padString);
  },

  StringPrototypeReplace(self, searchValue, replaceValue) {
    return self.replace(searchValue, replaceValue);
  },

  DatePrototypeGetDate(date) {
    return date.getDate();
  },

  DatePrototypeGetHours(date) {
    return date.getHours();
  },

  DatePrototypeGetMinutes(date) {
    return date.getMinutes();
  },

  DatePrototypeGetMonth(date) {
    return date.getMonth();
  },

  DatePrototypeGetSeconds(date) {
    return date.getSeconds();
  },

  Symbol,
  SymbolAsyncIterator: Symbol.asyncIterator,
  SymbolHasInstance: Symbol.hasInstance,
  SymbolIterator: Symbol.iterator,

  TypedArrayPrototypeSet(self, buf, len) {
    return self.set(buf, len);
  },

  decodeURIComponent,

  Uint8Array,
  Int8Array,
  Array,
  Date,

};
