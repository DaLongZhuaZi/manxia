const nodeInternalPrefix = "__node_internal_";
const {
  ObjectDefineProperty,
  ArrayIsArray,
  ArrayPrototypeIncludes,
  NumberIsNaN,
} = require("./primordials");
const hideStackFrames = (fn) => {
  // We rename the functions that will be hidden to cut off the stacktrace
  // at the outermost one
  const hidden = nodeInternalPrefix + fn.name;
  ObjectDefineProperty(fn, "name", { __proto__: null, value: hidden });
  return fn;
};
exports.validateString = hideStackFrames((value, name) => {
  if (typeof value !== "string") {
    throw new Error("ERR_INVALID_ARG_TYPE value:" + value + " name:" + name);
  }
});
exports.validateFunction = hideStackFrames((value, name) => {
  if (typeof value !== "function")
    throw new Error("ERR_INVALID_ARG_TYPE value:" + value + " name:" + name);
});
exports.validateAbortSignal = hideStackFrames((signal, name) => {
  if (
    signal !== undefined &&
    (signal === null || typeof signal !== "object" || !("aborted" in signal))
  ) {
    throw new Error("ERR_INVALID_ARG_TYPE value:" + value + " name:" + name);
  }
});

exports.validateObject = hideStackFrames((value, name, options) => {
  const useDefaultOptions = options == null;
  const allowArray = useDefaultOptions ? false : options.allowArray;
  const allowFunction = useDefaultOptions ? false : options.allowFunction;
  const nullable = useDefaultOptions ? false : options.nullable;
  if (
    (!nullable && value === null) ||
    (!allowArray && ArrayIsArray(value)) ||
    (typeof value !== "object" &&
      (!allowFunction || typeof value !== "function"))
  ) {
    throw new Error("ERR_INVALID_ARG_TYPE value:" + value + " name:" + name);
  }
});

exports.validateNumber = function validateNumber(
  value,
  name,
  min = undefined,
  max
) {
  if (typeof value !== "number")
    throw new Error("ERR_INVALID_ARG_TYPE value:" + value + " name:" + name);

  if (
    (min != null && value < min) ||
    (max != null && value > max) ||
    ((min != null || max != null) && NumberIsNaN(value))
  ) {
    throw new Error(
      "ERR_OUT_OF_RANGE, name:" +
        name +
        ", " +
        `${min != null ? `>= ${min}` : ""}${
          min != null && max != null ? " && " : ""
        }${max != null ? `<= ${max}` : ""}` +
        value
    );
  }
};

exports.validateBoolean = function validateBoolean(value, name) {
  if (typeof value !== "boolean")
    throw new Error("ERR_INVALID_ARG_TYPE value:" + value + " name:" + name);
};

exports.validateArray = hideStackFrames((value, name, minLength = 0) => {
  if (!Array.isArray(value)) {
    throw new Error("Array:" + name);
  }
  if (value.length < minLength) {
    const reason = `must be longer than ${minLength}`;
    throw new Error(
      "ERR_INVALID_ARG_VALUE name:" +
        name +
        ",value:" +
        value +
        ",reason:" +
        reason
    );
  }
});

exports.validateUnion = function validateUnion(value, name, union) {
  if (!ArrayPrototypeIncludes(union, value)) {
    throw new Error(
      "ERR_INVALID_ARG_TYPE, name:" +
        name +
        ",union:" +
        union +
        ",value:" +
        value
    );
  }
};
