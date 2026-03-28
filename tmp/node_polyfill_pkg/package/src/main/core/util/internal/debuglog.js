"use strict";
const process = require("@ohos.process");
const hilog = require("@ohos.hilog");
const util = require("@ohos.util");
const {
  ObjectCreate,
  ObjectDefineProperty,
  StringPrototypeToUpperCase,
  ArrayPrototypeSlice,
} = require("../../primordials");

let debugImpls = ObjectCreate(null);

const noop = () => {};

function debuglogImpl(enabled, set) {
  if (debugImpls[set] === undefined) {
    if (enabled) {
      const pid = process.pid;
      debugImpls[set] = function debug(format, ...args) {
        var msg = util.printf(format, ...args);
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

function debuglog(set, cb) {
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
  ObjectDefineProperty(logger, "enabled", {
    __proto__: null,
    get() {
      return test();
    },
    configurable: true,
    enumerable: true,
  });
  return logger;
}

module.exports = {
  debuglog,
};
