import { g as getDefaultExportFromCjs } from './_commonjsHelpers-YxXKG0rd.js';
import { p as primordials } from './primordials-4u6fpP8i.js';
import { v as validator } from './validator-4OkgCN7J.js';

var constants$1 = {
  // Alphabet chars.
  CHAR_UPPERCASE_A: 65 /* A */,
  CHAR_LOWERCASE_A: 97 /* a */,
  CHAR_UPPERCASE_Z: 90 /* Z */,
  CHAR_LOWERCASE_Z: 122 /* z */,
  CHAR_UPPERCASE_C: 67 /* C */,
  CHAR_LOWERCASE_B: 98 /* b */,
  CHAR_LOWERCASE_E: 101 /* e */,
  CHAR_LOWERCASE_N: 110 /* n */,

  // Non-alphabetic chars.
  CHAR_DOT: 46 /* . */,
  CHAR_FORWARD_SLASH: 47 /* / */,
  CHAR_BACKWARD_SLASH: 92 /* \ */,
  CHAR_VERTICAL_LINE: 124 /* | */,
  CHAR_COLON: 58 /* : */,
  CHAR_QUESTION_MARK: 63 /* ? */,
  CHAR_UNDERSCORE: 95 /* _ */,
  CHAR_LINE_FEED: 10 /* \n */,
  CHAR_CARRIAGE_RETURN: 13 /* \r */,
  CHAR_TAB: 9 /* \t */,
  CHAR_FORM_FEED: 12 /* \f */,
  CHAR_EXCLAMATION_MARK: 33 /* ! */,
  CHAR_HASH: 35 /* # */,
  CHAR_SPACE: 32 /*   */,
  CHAR_NO_BREAK_SPACE: 160 /* \u00A0 */,
  CHAR_ZERO_WIDTH_NOBREAK_SPACE: 65279 /* \uFEFF */,
  CHAR_LEFT_SQUARE_BRACKET: 91, //* [ */
  CHAR_RIGHT_SQUARE_BRACKET: 93 /* ] */,
  CHAR_LEFT_ANGLE_BRACKET: 60 /* < */,
  CHAR_RIGHT_ANGLE_BRACKET: 62 /* > */,
  CHAR_LEFT_CURLY_BRACKET: 123 /* { */,
  CHAR_RIGHT_CURLY_BRACKET: 125 /* } */,
  CHAR_HYPHEN_MINUS: 45 /* - */,
  CHAR_PLUS: 43 /* + */,
  CHAR_DOUBLE_QUOTE: 34 /* " */,
  CHAR_SINGLE_QUOTE: 39 /* ' */,
  CHAR_PERCENT: 37 /* % */,
  CHAR_SEMICOLON: 59 /* ; */,
  CHAR_CIRCUMFLEX_ACCENT: 94 /* ^ */,
  CHAR_GRAVE_ACCENT: 96 /* ` */,
  CHAR_AT: 64 /* @ */,
  CHAR_AMPERSAND: 38 /* & */,
  CHAR_EQUAL: 61 /* = */,

  // Digits
  CHAR_0: 48 /* 0 */,
  CHAR_9: 57 /* 9 */,

  EOL: "\n",
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
const constants = constants$1;
const {
  StringPrototypeCharCodeAt,
  StringPrototypeSlice,
  StringPrototypeLastIndexOf,
  FunctionPrototypeBind,
} = primordials;
const { validateString, validateObject } = validator;

var sep = "/";

function isPathSeparator(code) {
  return code === constants.CHAR_FORWARD_SLASH;
}

function _format(sep, pathObject) {
  validateObject(pathObject, "pathObject");
  const dir = pathObject.dir || pathObject.root;
  const base =
    pathObject.base || `${pathObject.name || ""}${pathObject.ext || ""}`;
  if (!dir) {
    return base;
  }
  return dir === pathObject.root ? `${dir}${base}` : `${dir}${sep}${base}`;
}

function basename(path, ext) {
  if (ext !== undefined) validateString(ext, "ext");
  validateString(path, "path");
  let start = 0;
  let end = -1;
  let matchedSlash = true;

  if (ext !== undefined && ext.length > 0 && ext.length <= path.length) {
    if (ext === path) return "";
    let extIdx = ext.length - 1;
    let firstNonSlashEnd = -1;
    for (let i = path.length - 1; i >= start; --i) {
      const code = StringPrototypeCharCodeAt(path, i);
      if (isPathSeparator(code)) {
        // If we reached a path separator that was not part of a set of path
        // separators at the end of the string, stop now
        if (!matchedSlash) {
          start = i + 1;
          break;
        }
      } else {
        if (firstNonSlashEnd === -1) {
          // We saw the first non-path separator, remember this index in case
          // we need it if the extension ends up not matching
          matchedSlash = false;
          firstNonSlashEnd = i + 1;
        }
        if (extIdx >= 0) {
          // Try to match the explicit extension
          if (code === StringPrototypeCharCodeAt(ext, extIdx)) {
            if (--extIdx === -1) {
              // We matched the extension, so mark this as the end of our path
              // component
              end = i;
            }
          } else {
            // Extension does not match, so our result is the entire path
            // component
            extIdx = -1;
            end = firstNonSlashEnd;
          }
        }
      }
    }

    if (start === end) end = firstNonSlashEnd;
    else if (end === -1) end = path.length;
    return StringPrototypeSlice(path, start, end);
  }
  for (let i = path.length - 1; i >= start; --i) {
    if (isPathSeparator(StringPrototypeCharCodeAt(path, i))) {
      // If we reached a path separator that was not part of a set of path
      // separators at the end of the string, stop now
      if (!matchedSlash) {
        start = i + 1;
        break;
      }
    } else if (end === -1) {
      // We saw the first non-path separator, mark this as the end of our
      // path component
      matchedSlash = false;
      end = i + 1;
    }
  }

  if (end === -1) return "";
  return StringPrototypeSlice(path, start, end);
}

function dirname(path) {
  validateString(path, "path");
  const len = path.length;
  if (len === 0) return ".";
  let rootEnd = -1;
  let offset = 0;
  const code = StringPrototypeCharCodeAt(path, 0);

  if (len === 1) {
    // `path` contains just a path separator, exit early to avoid
    // unnecessary work or a dot.
    return isPathSeparator(code) ? path : ".";
  }

  // Try to match a root
  if (isPathSeparator(code)) {
    // Possible UNC root

    rootEnd = offset = 1;

    if (isPathSeparator(StringPrototypeCharCodeAt(path, 1))) {
      // Matched double path separator at beginning
      let j = 2;
      let last = j;
      // Match 1 or more non-path separators
      while (j < len && !isPathSeparator(StringPrototypeCharCodeAt(path, j))) {
        j++;
      }
      if (j < len && j !== last) {
        // Matched!
        last = j;
        // Match 1 or more path separators
        while (j < len && isPathSeparator(StringPrototypeCharCodeAt(path, j))) {
          j++;
        }
        if (j < len && j !== last) {
          // Matched!
          last = j;
          // Match 1 or more non-path separators
          while (
            j < len &&
            !isPathSeparator(StringPrototypeCharCodeAt(path, j))
          ) {
            j++;
          }
          if (j === len) {
            // We matched a UNC root only
            return path;
          }
          if (j !== last) {
            // We matched a UNC root with leftovers

            // Offset by 1 to include the separator after the UNC root to
            // treat it as a "normal root" on top of a (UNC) root
            rootEnd = offset = j + 1;
          }
        }
      }
    }
    // Possible device root
  }

  let end = -1;
  let matchedSlash = true;
  for (let i = len - 1; i >= offset; --i) {
    if (isPathSeparator(StringPrototypeCharCodeAt(path, i))) {
      if (!matchedSlash) {
        end = i;
        break;
      }
    } else {
      // We saw the first non-path separator
      matchedSlash = false;
    }
  }

  if (end === -1) {
    if (rootEnd === -1) return ".";

    end = rootEnd;
  }
  return StringPrototypeSlice(path, 0, end);
}

function join(...args) {
  if (args.length === 0) return ".";
  let joined;
  for (let i = 0; i < args.length; ++i) {
    const arg = args[i];
    validateString(arg, "path");
    if (arg.length > 0) {
      if (joined === undefined) joined = arg;
      else joined += `/${arg}`;
    }
  }
  if (joined === undefined) return ".";
  return normalize(joined);
}

function normalize(path) {
  validateString(path, "path");

  if (path.length === 0) return ".";

  const isAbsolute =
    StringPrototypeCharCodeAt(path, 0) === constants.CHAR_FORWARD_SLASH;
  const trailingSeparator =
    StringPrototypeCharCodeAt(path, path.length - 1) ===
    constants.CHAR_FORWARD_SLASH;

  // Normalize the path
  path = normalizeString(path, !isAbsolute, "/");

  if (path.length === 0) {
    if (isAbsolute) return "/";
    return trailingSeparator ? "./" : ".";
  }
  if (trailingSeparator) path += "/";

  return isAbsolute ? `/${path}` : path;
}

function normalizeString(path, allowAboveRoot, separator) {
  let res = "";
  let lastSegmentLength = 0;
  let lastSlash = -1;
  let dots = 0;
  let code = 0;
  for (let i = 0; i <= path.length; ++i) {
    if (i < path.length) code = StringPrototypeCharCodeAt(path, i);
    else if (isPathSeparator(code)) break;
    else code = constants.CHAR_FORWARD_SLASH;

    if (isPathSeparator(code)) {
      if (lastSlash === i - 1 || dots === 1) ; else if (dots === 2) {
        if (
          res.length < 2 ||
          lastSegmentLength !== 2 ||
          StringPrototypeCharCodeAt(res, res.length - 1) !==
            constants.CHAR_DOT ||
          StringPrototypeCharCodeAt(res, res.length - 2) !== constants.CHAR_DOT
        ) {
          if (res.length > 2) {
            const lastSlashIndex = StringPrototypeLastIndexOf(res, separator);
            if (lastSlashIndex === -1) {
              res = "";
              lastSegmentLength = 0;
            } else {
              res = StringPrototypeSlice(res, 0, lastSlashIndex);
              lastSegmentLength =
                res.length - 1 - StringPrototypeLastIndexOf(res, separator);
            }
            lastSlash = i;
            dots = 0;
            continue;
          } else if (res.length !== 0) {
            res = "";
            lastSegmentLength = 0;
            lastSlash = i;
            dots = 0;
            continue;
          }
        }
        if (allowAboveRoot) {
          res += res.length > 0 ? `${separator}..` : "..";
          lastSegmentLength = 2;
        }
      } else {
        if (res.length > 0)
          res += `${separator}${StringPrototypeSlice(path, lastSlash + 1, i)}`;
        else res = StringPrototypeSlice(path, lastSlash + 1, i);
        lastSegmentLength = i - lastSlash - 1;
      }
      lastSlash = i;
      dots = 0;
    } else if (code === constants.CHAR_DOT && dots !== -1) {
      ++dots;
    } else {
      dots = -1;
    }
  }
  return res;
}

function resolve(...args) {
  let resolvedPath = "";
  let resolvedAbsolute = false;

  for (let i = args.length - 1; i >= -1 && !resolvedAbsolute; i--) {
    const path = i >= 0 ? args[i] : sep;

    validateString(path, "path");

    // Skip empty entries
    if (path.length === 0) {
      continue;
    }

    resolvedPath = `${path}/${resolvedPath}`;
    resolvedAbsolute =
      StringPrototypeCharCodeAt(path, 0) === constants.CHAR_FORWARD_SLASH;
  }

  // At this point the path should be resolved to a full absolute path, but
  // handle relative paths to be safe (might happen when process.cwd() fails)

  // Normalize the path
  resolvedPath = normalizeString(resolvedPath, !resolvedAbsolute, "/");

  if (resolvedAbsolute) {
    return `/${resolvedPath}`;
  }
  return resolvedPath.length > 0 ? resolvedPath : ".";
}

function isAbsolute(path) {
  validateString(path, "path");
  return (
    path.length > 0 &&
    StringPrototypeCharCodeAt(path, 0) === constants.CHAR_FORWARD_SLASH
  );
}

function relative(from, to) {
  validateString(from, "from");
  validateString(to, "to");

  if (from === to) return "";

  // Trim leading forward slashes.
  from = resolve(from);
  to = resolve(to);

  if (from === to) return "";

  const fromStart = 1;
  const fromEnd = from.length;
  const fromLen = fromEnd - fromStart;
  const toStart = 1;
  const toLen = to.length - toStart;

  // Compare paths to find the longest common path from root
  const length = fromLen < toLen ? fromLen : toLen;
  let lastCommonSep = -1;
  let i = 0;
  for (; i < length; i++) {
    const fromCode = StringPrototypeCharCodeAt(from, fromStart + i);
    if (fromCode !== StringPrototypeCharCodeAt(to, toStart + i)) break;
    else if (fromCode === constants.CHAR_FORWARD_SLASH) lastCommonSep = i;
  }
  if (i === length) {
    if (toLen > length) {
      if (
        StringPrototypeCharCodeAt(to, toStart + i) ===
        constants.CHAR_FORWARD_SLASH
      ) {
        // We get here if `from` is the exact base path for `to`.
        // For example: from='/foo/bar'; to='/foo/bar/baz'
        return StringPrototypeSlice(to, toStart + i + 1);
      }
      if (i === 0) {
        // We get here if `from` is the root
        // For example: from='/'; to='/foo'
        return StringPrototypeSlice(to, toStart + i);
      }
    } else if (fromLen > length) {
      if (
        StringPrototypeCharCodeAt(from, fromStart + i) ===
        constants.CHAR_FORWARD_SLASH
      ) {
        // We get here if `to` is the exact base path for `from`.
        // For example: from='/foo/bar/baz'; to='/foo/bar'
        lastCommonSep = i;
      } else if (i === 0) {
        // We get here if `to` is the root.
        // For example: from='/foo/bar'; to='/'
        lastCommonSep = 0;
      }
    }
  }

  let out = "";
  // Generate the relative path based on the path difference between `to`
  // and `from`.
  for (i = fromStart + lastCommonSep + 1; i <= fromEnd; ++i) {
    if (
      i === fromEnd ||
      StringPrototypeCharCodeAt(from, i) === constants.CHAR_FORWARD_SLASH
    ) {
      out += out.length === 0 ? ".." : "/..";
    }
  }

  // Lastly, append the rest of the destination (`to`) path that comes after
  // the common path parts.
  return `${out}${StringPrototypeSlice(to, toStart + lastCommonSep)}`;
}

function extname(path) {
  validateString(path, "path");
  let startDot = -1;
  let startPart = 0;
  let end = -1;
  let matchedSlash = true;
  // Track the state of characters (if any) we see before our first dot and
  // after any path separator we find
  let preDotState = 0;
  for (let i = path.length - 1; i >= 0; --i) {
    path.charcode;
    const code = StringPrototypeCharCodeAt(path, i);
    if (code === constants.CHAR_FORWARD_SLASH) {
      // If we reached a path separator that was not part of a set of path
      // separators at the end of the string, stop now
      if (!matchedSlash) {
        startPart = i + 1;
        break;
      }
      continue;
    }
    if (end === -1) {
      // We saw the first non-path separator, mark this as the end of our
      // extension
      matchedSlash = false;
      end = i + 1;
    }
    if (code === constants.CHAR_DOT) {
      // If this is our first dot, mark it as the start of our extension
      if (startDot === -1) startDot = i;
      else if (preDotState !== 1) preDotState = 1;
    } else if (startDot !== -1) {
      // We saw a non-dot and non-path separator before our dot, so we should
      // have a good chance at having a non-empty extension
      preDotState = -1;
    }
  }

  if (
    startDot === -1 ||
    end === -1 ||
    // We saw a non-dot character immediately before the dot
    preDotState === 0 ||
    // The (right-most) trimmed path component is exactly '..'
    (preDotState === 1 && startDot === end - 1 && startDot === startPart + 1)
  ) {
    return "";
  }
  return StringPrototypeSlice(path, startDot, end);
}

const format = FunctionPrototypeBind(_format, null, "/");

function parse(path) {
  validateString(path, "path");

  const ret = { root: "", dir: "", base: "", ext: "", name: "" };
  if (path.length === 0) return ret;
  const isAbsolute =
    StringPrototypeCharCodeAt(path, 0) === constants.CHAR_FORWARD_SLASH;
  let start;
  if (isAbsolute) {
    ret.root = "/";
    start = 1;
  } else {
    start = 0;
  }
  let startDot = -1;
  let startPart = 0;
  let end = -1;
  let matchedSlash = true;
  let i = path.length - 1;

  // Track the state of characters (if any) we see before our first dot and
  // after any path separator we find
  let preDotState = 0;

  // Get non-dir info
  for (; i >= start; --i) {
    const code = StringPrototypeCharCodeAt(path, i);
    if (code === constants.CHAR_FORWARD_SLASH) {
      // If we reached a path separator that was not part of a set of path
      // separators at the end of the string, stop now
      if (!matchedSlash) {
        startPart = i + 1;
        break;
      }
      continue;
    }
    if (end === -1) {
      // We saw the first non-path separator, mark this as the end of our
      // extension
      matchedSlash = false;
      end = i + 1;
    }
    if (code === constants.CHAR_DOT) {
      // If this is our first dot, mark it as the start of our extension
      if (startDot === -1) startDot = i;
      else if (preDotState !== 1) preDotState = 1;
    } else if (startDot !== -1) {
      // We saw a non-dot and non-path separator before our dot, so we should
      // have a good chance at having a non-empty extension
      preDotState = -1;
    }
  }

  if (end !== -1) {
    const start = startPart === 0 && isAbsolute ? 1 : startPart;
    if (
      startDot === -1 ||
      // We saw a non-dot character immediately before the dot
      preDotState === 0 ||
      // The (right-most) trimmed path component is exactly '..'
      (preDotState === 1 && startDot === end - 1 && startDot === startPart + 1)
    ) {
      ret.base = ret.name = StringPrototypeSlice(path, start, end);
    } else {
      ret.name = StringPrototypeSlice(path, start, startDot);
      ret.base = StringPrototypeSlice(path, start, end);
      ret.ext = StringPrototypeSlice(path, startDot, end);
    }
  }

  if (startPart > 0) ret.dir = StringPrototypeSlice(path, 0, startPart - 1);
  else if (isAbsolute) ret.dir = "/";

  return ret;
}

var path = {
  basename,
  dirname,
  extname,
  format,
  parse,
  sep,
  join,
  resolve,
  isAbsolute,
  relative,
  normalize,
};

var index = /*@__PURE__*/getDefaultExportFromCjs(path);

export { constants$1 as c, index as i, path as p };
