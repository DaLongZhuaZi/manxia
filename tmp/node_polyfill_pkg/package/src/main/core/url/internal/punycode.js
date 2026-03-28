

const utf16 = {
    decode: function (input) {
        var output = [], i = 0, len = input.length, value, extra;
        while (i < len) {
            value = input.charCodeAt(i++);
            if ((value & 0xF800) === 0xD800) {
                extra = input.charCodeAt(i++);
                if (((value & 0xFC00) !== 0xD800) || ((extra & 0xFC00) !== 0xDC00)) {
                    throw new RangeError("UTF-16(decode): Illegal UTF-16 sequence");
                }
                value = ((value & 0x3FF) << 10) + (extra & 0x3FF) + 0x10000;
            }
            output.push(value);
        }
        return output;
    },
    encode: function (input) {
        var output = [], i = 0, len = input.length, value;
        while (i < len) {
            value = input[i++];
            if ((value & 0xF800) === 0xD800) {
                throw new RangeError("UTF-16(encode): Illegal UTF-16 value");
            }
            if (value > 0xFFFF) {
                value -= 0x10000;
                output.push(String.fromCharCode(((value >>> 10) & 0x3FF) | 0xD800));
                value = 0xDC00 | (value & 0x3FF);
            }
            output.push(String.fromCharCode(value));
        }
        return output.join("");
    }
}

var initial_n = 0x80;
var initial_bias = 72;
var delimiter = "-";
var base = 36;
var damp = 700;
var tmin = 1;
var tmax = 26;
var skew = 38;
var maxint = 0x7FFFFFFF;

function decode_digit(cp) {
    return cp - 48 < 10 ? cp - 22 : cp - 65 < 26 ? cp - 65 : cp - 97 < 26 ? cp - 97 : base;
}

function encode_digit(d, flag) {
    return d + 22 + Number(75 * Number((d < 26))) - ((Number(flag != 0)) << 5);

}

function adapt(delta, numpoints, firsttime) {
    var k;
    delta = firsttime ? Math.floor(delta / damp) : (delta >> 1);
    delta += Math.floor(delta / numpoints);

    for (k = 0; delta > (((base - tmin) * tmax) >> 1); k += base) {
        delta = Math.floor(delta / (base - tmin));
    }
    return Math.floor(k + (base - tmin + 1) * delta / (delta + skew));
}


function encode_basic(bcp, flag) {
    bcp -= Number((bcp - 97 < 26)) << 5;
    return bcp + ((!flag && Number((bcp - 65 < 26))) << 5);
}

function decode(input, preserveCase) {
    var output = [];
    var case_flags = [];
    var input_length = input.length;

    var n, out, i, bias, basic, j, ic, oldi, w, k, digit, t, len;

    n = initial_n;
    i = 0;
    bias = initial_bias;

    basic = input.lastIndexOf(delimiter);
    if (basic < 0) basic = 0;

    for (j = 0; j < basic; ++j) {
        if (preserveCase) case_flags[output.length] = (input.charCodeAt(j) - 65 < 26);
        if (input.charCodeAt(j) >= 0x80) {
            throw new RangeError("Illegal input >= 0x80");
        }
        output.push(input.charCodeAt(j));
    }

    for (ic = basic > 0 ? basic + 1 : 0; ic < input_length; ) {

        for (oldi = i, w = 1, k = base;; k += base) {
            if (ic >= input_length) {
                throw RangeError("punycode_bad_input(1)");
            }
            digit = decode_digit(input.charCodeAt(ic++));

            if (digit >= base) {
                throw RangeError("punycode_bad_input(2)");
            }
            if (digit > Math.floor((maxint - i) / w)) {
                throw RangeError("punycode_overflow(1)");
            }
            i += digit * w;
            t = k <= bias ? tmin : k >= bias + tmax ? tmax : k - bias;
            if (digit < t) {
                break;
            }
            if (w > Math.floor(maxint / (base - t))) {
                throw RangeError("punycode_overflow(2)");
            }
            w *= (base - t);
        }

        out = output.length + 1;
        bias = adapt(i - oldi, out, oldi === 0);

        if (Math.floor(i / out) > maxint - n) {
            throw RangeError("punycode_overflow(3)");
        }
        n += Math.floor(i / out);
        i %= out;

        if (preserveCase) {
            case_flags.splice(i, 0, input.charCodeAt(ic - 1) - 65 < 26);
        }

        output.splice(i, 0, n);
        i++;
    }
    if (preserveCase) {
        for (i = 0, len = output.length; i < len; i++) {
            if (case_flags[i]) {
                output[i] = (String.fromCharCode(output[i]).toUpperCase()).charCodeAt(0);
            }
        }
    }
    return utf16.encode(output);
};


function encode(input, preserveCase) {
    var n, delta, h, b, bias, j, m, q, k, t, ijv, case_flags;

    if (preserveCase) {
        case_flags = utf16.decode(input);
    }
    input = utf16.decode(input.toLowerCase());

    var input_length = input.length; // Cache the length

    if (preserveCase) {
        for (j = 0; j < input_length; j++) {
            case_flags[j] = input[j] != case_flags[j];
        }
    }

    var output = [];
    n = initial_n;
    delta = 0;
    bias = initial_bias;

    for (j = 0; j < input_length; ++j) {
        if (input[j] < 0x80) {
            output.push(
            String.fromCharCode(
                    case_flags ? encode_basic(input[j], case_flags[j]) : input[j]
            )
            );
        }
    }

    h = b = output.length;

    if (b > 0) output.push(delimiter);

    while (h < input_length) {
        for (m = maxint, j = 0; j < input_length; ++j) {
            ijv = input[j];
            if (ijv >= n && ijv < m) m = ijv;
        }

        if (m - n > Math.floor((maxint - delta) / (h + 1))) {
            throw RangeError("punycode_overflow (1)");
        }
        delta += (m - n) * (h + 1);
        n = m;

        for (j = 0; j < input_length; ++j) {
            ijv = input[j];

            if (ijv < n) {
                if (++delta > maxint) return Error("punycode_overflow(2)");
            }

            if (ijv == n) {
                for (q = delta, k = base;; k += base) {
                    t = k <= bias ? tmin : k >= bias + tmax ? tmax : k - bias;
                    if (q < t) break;
                    output.push(String.fromCharCode(encode_digit(t + (q - t) % (base - t), 0)));
                    q = Math.floor((q - t) / (base - t));
                }
                output.push(String.fromCharCode(encode_digit(q, preserveCase && case_flags[j] ? 1 : 0)));
                bias = adapt(delta, h + 1, h == b);
                delta = 0;
                ++h;
            }
        }

        ++delta, ++n;
    }
    return output.join("");
}

module.exports = {
    decode,
    encode,
}