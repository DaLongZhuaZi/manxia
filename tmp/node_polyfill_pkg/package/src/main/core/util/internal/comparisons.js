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
};

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

module.exports = {
    isDeepStrictEqual: deepEqual
}