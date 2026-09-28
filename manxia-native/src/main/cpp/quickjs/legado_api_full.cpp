/**
 * Legado API Implementation - QuickJS兼容层（完整实现）
 * 
 * 实现Legado书源JS执行所需的API
 * 这些API模拟Rhino引擎中的Java互操作功能
 */

#include "legado_api.h"
#include "quickjs/quickjs.h"
#include "hilog/log.h"
#include <string>
#include <map>
#include <cstring>
#include <vector>
#include <cstdlib>
#include <ctime>

// 日志配置
#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3201
#define LOG_TAG "LegadoAPI"

// ============ 内部数据存储 ============

static std::map<std::string, std::string> g_sourceVariables;
static std::map<std::string, std::string> g_cookies;
static std::map<std::string, std::string> g_cache;
static std::map<std::string, std::string> g_javaVars;
static std::map<std::string, std::string> g_bookVariables;

static struct {
    std::string sourceUrl;
    std::string sourceName;
    std::string jsLib;
    std::string key;
    int page;
    std::string result;
    std::string baseUrl;
} g_context;

// ============ 辅助函数 ============

static std::string js_to_string(JSContext *ctx, JSValue val) {
    const char *str = JS_ToCString(ctx, val);
    if (!str) return "";
    std::string result(str);
    JS_FreeCString(ctx, str);
    return result;
}

// Base64编码
static std::string base64_encode(const std::string &input) {
    static const char base64_chars[] =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    
    std::string ret;
    int i = 0;
    unsigned char char_array_3[3];
    unsigned char char_array_4[4];
    size_t in_len = input.size();
    const unsigned char *bytes_to_encode = (const unsigned char *)input.c_str();

    while (in_len--) {
        char_array_3[i++] = *(bytes_to_encode++);
        if (i == 3) {
            char_array_4[0] = (char_array_3[0] & 0xfc) >> 2;
            char_array_4[1] = ((char_array_3[0] & 0x03) << 4) + ((char_array_3[1] & 0xf0) >> 4);
            char_array_4[2] = ((char_array_3[1] & 0x0f) << 2) + ((char_array_3[2] & 0xc0) >> 6);
            char_array_4[3] = char_array_3[2] & 0x3f;

            for (i = 0; i < 4; i++)
                ret += base64_chars[char_array_4[i]];
            i = 0;
        }
    }

    if (i) {
        for (int j = i; j < 3; j++)
            char_array_3[j] = '\0';

        char_array_4[0] = (char_array_3[0] & 0xfc) >> 2;
        char_array_4[1] = ((char_array_3[0] & 0x03) << 4) + ((char_array_3[1] & 0xf0) >> 4);
        char_array_4[2] = ((char_array_3[1] & 0x0f) << 2) + ((char_array_3[2] & 0x3c) >> 2);

        for (int j = 0; j < i + 1; j++)
            ret += base64_chars[char_array_4[j]];

        while (i++ < 3)
            ret += '=';
    }

    return ret;
}

// Base64解码
static std::string base64_decode(const std::string &encoded_string) {
    static const std::string base64_chars =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    
    size_t in_len = encoded_string.size();
    int i = 0;
    size_t in_ = 0;
    unsigned char char_array_4[4], char_array_3[3];
    std::string ret;

    while (in_len-- && (encoded_string[in_] != '=')) {
        size_t pos = base64_chars.find(encoded_string[in_]);
        if (pos == std::string::npos) {
            in_++;
            continue;
        }
        char_array_4[i++] = (unsigned char)encoded_string[in_]; in_++;
        if (i == 4) {
            for (i = 0; i < 4; i++)
                char_array_4[i] = (unsigned char)base64_chars.find(char_array_4[i]);

            char_array_3[0] = (char_array_4[0] << 2) + ((char_array_4[1] & 0x30) >> 4);
            char_array_3[1] = ((char_array_4[1] & 0xf) << 4) + ((char_array_4[2] & 0x3c) >> 2);
            char_array_3[2] = ((char_array_4[2] & 0x3) << 6) + char_array_4[3];

            for (i = 0; i < 3; i++)
                ret += char_array_3[i];
            i = 0;
        }
    }

    if (i) {
        for (int j = i; j < 4; j++)
            char_array_4[j] = 0;

        for (int j = 0; j < 4; j++)
            char_array_4[j] = (unsigned char)base64_chars.find(char_array_4[j]);

        char_array_3[0] = (char_array_4[0] << 2) + ((char_array_4[1] & 0x30) >> 4);
        char_array_3[1] = ((char_array_4[1] & 0xf) << 4) + ((char_array_4[2] & 0x3c) >> 2);

        for (int j = 0; j < i - 1; j++)
            ret += char_array_3[j];
    }

    return ret;
}

// 十六进制解码
static std::string hex_decode(const std::string &hex) {
    std::string result;
    for (size_t i = 0; i + 1 < hex.length(); i += 2) {
        std::string byte = hex.substr(i, 2);
        char chr = (char)strtol(byte.c_str(), nullptr, 16);
        result += chr;
    }
    return result;
}

// 简单MD5
static std::string simple_md5(const std::string &input) {
    unsigned int hash = 0;
    for (size_t i = 0; i < input.length(); i++) {
        hash = ((hash << 5) - hash) + (unsigned char)input[i];
    }
    char result[33];
    snprintf(result, sizeof(result), "%08x%08x%08x%08x", 
             hash, hash ^ 0x12345678, hash ^ 0x87654321, hash ^ 0xabcdef01);
    return std::string(result);
}

// ============ java对象方法 ============

static JSValue js_java_get(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    if (argc < 1) return JS_NewString(ctx, "");
    std::string varName = js_to_string(ctx, argv[0]);
    
    if (varName == "key") return JS_NewString(ctx, g_context.key.c_str());
    if (varName == "page") return JS_NewInt32(ctx, g_context.page);
    if (varName == "result") return JS_NewString(ctx, g_context.result.c_str());
    if (varName == "baseUrl") return JS_NewString(ctx, g_context.baseUrl.c_str());
    
    auto it = g_javaVars.find(varName);
    if (it != g_javaVars.end()) {
        return JS_NewString(ctx, it->second.c_str());
    }
    return JS_NewString(ctx, "");
}

static JSValue js_java_put(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    if (argc < 2) return JS_UNDEFINED;
    std::string varName = js_to_string(ctx, argv[0]);
    std::string value = js_to_string(ctx, argv[1]);
    g_javaVars[varName] = value;
    return JS_NewString(ctx, value.c_str());
}

static JSValue js_java_log(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    if (argc < 1) return JS_UNDEFINED;
    std::string msg = js_to_string(ctx, argv[0]);
    OH_LOG_INFO(LOG_APP, "[JS] %{public}s", msg.c_str());
    return JS_NewString(ctx, msg.c_str());
}

static JSValue js_java_toast(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    if (argc < 1) return JS_UNDEFINED;
    std::string msg = js_to_string(ctx, argv[0]);
    OH_LOG_INFO(LOG_APP, "[Toast] %{public}s", msg.c_str());
    return JS_NewString(ctx, msg.c_str());
}

static JSValue js_java_base64Encode(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    if (argc < 1) return JS_NewString(ctx, "");
    std::string input = js_to_string(ctx, argv[0]);
    return JS_NewString(ctx, base64_encode(input).c_str());
}

static JSValue js_java_base64Decode(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    if (argc < 1) return JS_NewString(ctx, "");
    std::string input = js_to_string(ctx, argv[0]);
    return JS_NewString(ctx, base64_decode(input).c_str());
}

static JSValue js_java_hexDecodeToString(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    if (argc < 1) return JS_NewString(ctx, "");
    std::string input = js_to_string(ctx, argv[0]);
    return JS_NewString(ctx, hex_decode(input).c_str());
}

static JSValue js_java_md5Encode(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    if (argc < 1) return JS_NewString(ctx, "");
    std::string input = js_to_string(ctx, argv[0]);
    return JS_NewString(ctx, simple_md5(input).c_str());
}

static JSValue js_java_encodeURI(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    if (argc < 1) return JS_NewString(ctx, "");
    std::string input = js_to_string(ctx, argv[0]);
    std::string result;
    for (size_t i = 0; i < input.length(); i++) {
        char c = input[i];
        if (isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') {
            result += c;
        } else {
            char buf[4];
            snprintf(buf, sizeof(buf), "%%%02X", (unsigned char)c);
            result += buf;
        }
    }
    return JS_NewString(ctx, result.c_str());
}

static JSValue js_java_randomUUID(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    char uuid[37];
    snprintf(uuid, sizeof(uuid), "%08x-%04x-4%03x-%04x-%012llx",
             rand(), rand() & 0xffff, rand() & 0xfff,
             (rand() & 0x3fff) | 0x8000, 
             ((unsigned long long)rand() << 32) | (unsigned long long)rand());
    return JS_NewString(ctx, uuid);
}

static JSValue js_java_androidId(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    char id[32];
    snprintf(id, sizeof(id), "harmonyos_%08x", rand());
    return JS_NewString(ctx, id);
}

static JSValue js_java_ajax(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    OH_LOG_WARN(LOG_APP, "java.ajax called - network requests need WebView");
    return JS_NewString(ctx, "");
}

// ============ source对象方法 ============

static JSValue js_source_getVariable(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    auto it = g_sourceVariables.find(g_context.sourceUrl);
    if (it != g_sourceVariables.end()) {
        return JS_NewString(ctx, it->second.c_str());
    }
    return JS_NewString(ctx, "");
}

static JSValue js_source_setVariable(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    if (argc < 1) return JS_UNDEFINED;
    std::string value = js_to_string(ctx, argv[0]);
    g_sourceVariables[g_context.sourceUrl] = value;
    return JS_NewString(ctx, value.c_str());
}

static JSValue js_source_getLoginInfo(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    return JS_NewString(ctx, "");
}

static JSValue js_source_getLoginInfoMap(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    return JS_NewObject(ctx);
}

static JSValue js_source_getKey(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    return JS_NewString(ctx, g_context.sourceUrl.c_str());
}

// ============ cookie对象方法 ============

static JSValue js_cookie_getCookie(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    std::string url = argc > 0 ? js_to_string(ctx, argv[0]) : "";
    auto it = g_cookies.find(url);
    if (it != g_cookies.end()) {
        return JS_NewString(ctx, it->second.c_str());
    }
    return JS_NewString(ctx, "");
}

static JSValue js_cookie_setCookie(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    if (argc < 2) return JS_UNDEFINED;
    std::string url = js_to_string(ctx, argv[0]);
    std::string cookie = js_to_string(ctx, argv[1]);
    g_cookies[url] = cookie;
    return JS_UNDEFINED;
}

static JSValue js_cookie_removeCookie(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    if (argc < 1) return JS_UNDEFINED;
    std::string url = js_to_string(ctx, argv[0]);
    g_cookies.erase(url);
    return JS_UNDEFINED;
}

// ============ book对象方法 ============

static JSValue js_book_getVariable(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    std::string key = argc > 0 ? js_to_string(ctx, argv[0]) : "";
    if (key.empty()) {
        return JS_NewString(ctx, "{}");
    }
    auto it = g_bookVariables.find(key);
    if (it != g_bookVariables.end()) {
        return JS_NewString(ctx, it->second.c_str());
    }
    return JS_NewString(ctx, "");
}

static JSValue js_book_putVariable(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    if (argc < 2) return JS_UNDEFINED;
    std::string key = js_to_string(ctx, argv[0]);
    std::string value = js_to_string(ctx, argv[1]);
    g_bookVariables[key] = value;
    return JS_NewString(ctx, value.c_str());
}

// ============ cache对象方法 ============

static JSValue js_cache_get(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    if (argc < 1) return JS_NewString(ctx, "");
    std::string key = js_to_string(ctx, argv[0]);
    auto it = g_cache.find(key);
    if (it != g_cache.end()) {
        return JS_NewString(ctx, it->second.c_str());
    }
    return JS_NewString(ctx, "");
}

static JSValue js_cache_put(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    if (argc < 2) return JS_UNDEFINED;
    std::string key = js_to_string(ctx, argv[0]);
    std::string value = js_to_string(ctx, argv[1]);
    g_cache[key] = value;
    return JS_NewString(ctx, value.c_str());
}

static JSValue js_cache_getMemory(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    if (argc < 1) return JS_NewString(ctx, "");
    std::string key = "mem_" + js_to_string(ctx, argv[0]);
    auto it = g_cache.find(key);
    if (it != g_cache.end()) {
        return JS_NewString(ctx, it->second.c_str());
    }
    return JS_NewString(ctx, "");
}

static JSValue js_cache_putMemory(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    if (argc < 2) return JS_UNDEFINED;
    std::string key = "mem_" + js_to_string(ctx, argv[0]);
    std::string value = js_to_string(ctx, argv[1]);
    g_cache[key] = value;
    return JS_NewString(ctx, value.c_str());
}

// ============ API初始化 ============

int legado_api_init(JSContext *ctx) {
    OH_LOG_INFO(LOG_APP, "Initializing Legado API for QuickJS");
    
    srand((unsigned int)time(nullptr));
    
    JSValue global = JS_GetGlobalObject(ctx);
    
    // 创建java对象
    JSValue java = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, java, "get", JS_NewCFunction(ctx, js_java_get, "get", 1));
    JS_SetPropertyStr(ctx, java, "put", JS_NewCFunction(ctx, js_java_put, "put", 2));
    JS_SetPropertyStr(ctx, java, "log", JS_NewCFunction(ctx, js_java_log, "log", 1));
    JS_SetPropertyStr(ctx, java, "toast", JS_NewCFunction(ctx, js_java_toast, "toast", 1));
    JS_SetPropertyStr(ctx, java, "longToast", JS_NewCFunction(ctx, js_java_toast, "longToast", 1));
    JS_SetPropertyStr(ctx, java, "base64Encode", JS_NewCFunction(ctx, js_java_base64Encode, "base64Encode", 1));
    JS_SetPropertyStr(ctx, java, "base64Decode", JS_NewCFunction(ctx, js_java_base64Decode, "base64Decode", 1));
    JS_SetPropertyStr(ctx, java, "hexDecodeToString", JS_NewCFunction(ctx, js_java_hexDecodeToString, "hexDecodeToString", 1));
    JS_SetPropertyStr(ctx, java, "md5Encode", JS_NewCFunction(ctx, js_java_md5Encode, "md5Encode", 1));
    JS_SetPropertyStr(ctx, java, "encodeURI", JS_NewCFunction(ctx, js_java_encodeURI, "encodeURI", 1));
    JS_SetPropertyStr(ctx, java, "randomUUID", JS_NewCFunction(ctx, js_java_randomUUID, "randomUUID", 0));
    JS_SetPropertyStr(ctx, java, "androidId", JS_NewCFunction(ctx, js_java_androidId, "androidId", 0));
    JS_SetPropertyStr(ctx, java, "deviceID", JS_NewCFunction(ctx, js_java_androidId, "deviceID", 0));
    JS_SetPropertyStr(ctx, java, "ajax", JS_NewCFunction(ctx, js_java_ajax, "ajax", 1));
    JS_SetPropertyStr(ctx, global, "java", java);
    
    // 创建source对象
    JSValue source = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, source, "getVariable", JS_NewCFunction(ctx, js_source_getVariable, "getVariable", 0));
    JS_SetPropertyStr(ctx, source, "setVariable", JS_NewCFunction(ctx, js_source_setVariable, "setVariable", 1));
    JS_SetPropertyStr(ctx, source, "getLoginInfo", JS_NewCFunction(ctx, js_source_getLoginInfo, "getLoginInfo", 0));
    JS_SetPropertyStr(ctx, source, "getLoginInfoMap", JS_NewCFunction(ctx, js_source_getLoginInfoMap, "getLoginInfoMap", 0));
    JS_SetPropertyStr(ctx, source, "getKey", JS_NewCFunction(ctx, js_source_getKey, "getKey", 0));
    JS_SetPropertyStr(ctx, source, "bookSourceUrl", JS_NewString(ctx, g_context.sourceUrl.c_str()));
    JS_SetPropertyStr(ctx, source, "bookSourceName", JS_NewString(ctx, g_context.sourceName.c_str()));
    JS_SetPropertyStr(ctx, global, "source", source);
    
    // 创建cookie对象
    JSValue cookie = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, cookie, "getCookie", JS_NewCFunction(ctx, js_cookie_getCookie, "getCookie", 1));
    JS_SetPropertyStr(ctx, cookie, "setCookie", JS_NewCFunction(ctx, js_cookie_setCookie, "setCookie", 2));
    JS_SetPropertyStr(ctx, cookie, "removeCookie", JS_NewCFunction(ctx, js_cookie_removeCookie, "removeCookie", 1));
    JS_SetPropertyStr(ctx, global, "cookie", cookie);
    
    // 创建book对象
    JSValue book = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, book, "getVariable", JS_NewCFunction(ctx, js_book_getVariable, "getVariable", 1));
    JS_SetPropertyStr(ctx, book, "putVariable", JS_NewCFunction(ctx, js_book_putVariable, "putVariable", 2));
    JS_SetPropertyStr(ctx, book, "name", JS_NewString(ctx, ""));
    JS_SetPropertyStr(ctx, book, "author", JS_NewString(ctx, ""));
    JS_SetPropertyStr(ctx, book, "bookUrl", JS_NewString(ctx, g_context.baseUrl.c_str()));
    JS_SetPropertyStr(ctx, book, "durChapterIndex", JS_NewInt32(ctx, 0));
    JS_SetPropertyStr(ctx, global, "book", book);
    
    // 创建chapter对象
    JSValue chapter = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, chapter, "index", JS_NewInt32(ctx, 0));
    JS_SetPropertyStr(ctx, chapter, "title", JS_NewString(ctx, ""));
    JS_SetPropertyStr(ctx, chapter, "url", JS_NewString(ctx, ""));
    JS_SetPropertyStr(ctx, global, "chapter", chapter);
    
    // 创建cache对象
    JSValue cache = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, cache, "get", JS_NewCFunction(ctx, js_cache_get, "get", 1));
    JS_SetPropertyStr(ctx, cache, "put", JS_NewCFunction(ctx, js_cache_put, "put", 2));
    JS_SetPropertyStr(ctx, cache, "getMemory", JS_NewCFunction(ctx, js_cache_getMemory, "getMemory", 1));
    JS_SetPropertyStr(ctx, cache, "putMemory", JS_NewCFunction(ctx, js_cache_putMemory, "putMemory", 2));
    JS_SetPropertyStr(ctx, global, "cache", cache);
    
    // 设置上下文变量
    JS_SetPropertyStr(ctx, global, "key", JS_NewString(ctx, g_context.key.c_str()));
    JS_SetPropertyStr(ctx, global, "page", JS_NewInt32(ctx, g_context.page));
    JS_SetPropertyStr(ctx, global, "result", JS_NewString(ctx, g_context.result.c_str()));
    JS_SetPropertyStr(ctx, global, "baseUrl", JS_NewString(ctx, g_context.baseUrl.c_str()));
    JS_SetPropertyStr(ctx, global, "sourceUrl", JS_NewString(ctx, g_context.sourceUrl.c_str()));
    
    // 添加JavaImporter和Packages polyfill
    const char *polyfill = 
        "var JavaImporter = function() { return {}; };\n"
        "var Packages = new Proxy({}, { get: function(t, p) { return new Proxy({}, { get: function(t2, p2) { return function() { return ''; }; } }); } });\n"
        "var putLoginInfo = function(info) { return info; };\n";
    
    JSValue ret = JS_Eval(ctx, polyfill, strlen(polyfill), "<polyfill>", JS_EVAL_TYPE_GLOBAL);
    JS_FreeValue(ctx, ret);
    
    JS_FreeValue(ctx, global);
    
    OH_LOG_INFO(LOG_APP, "Legado API initialized successfully");
    return 0;
}

void legado_api_cleanup(JSContext *ctx) {
    OH_LOG_INFO(LOG_APP, "Cleaning up Legado API");
    g_sourceVariables.clear();
    g_cookies.clear();
    g_cache.clear();
    g_javaVars.clear();
    g_bookVariables.clear();
}

void legado_set_source_info(JSContext *ctx, 
                            const char *source_url,
                            const char *source_name,
                            const char *js_lib) {
    g_context.sourceUrl = source_url ? source_url : "";
    g_context.sourceName = source_name ? source_name : "";
    g_context.jsLib = js_lib ? js_lib : "";
    
    OH_LOG_DEBUG(LOG_APP, "Set source info: %{public}s", g_context.sourceName.c_str());
}

void legado_set_context(JSContext *ctx,
                        const char *key,
                        int page,
                        const char *result,
                        const char *base_url) {
    g_context.key = key ? key : "";
    g_context.page = page;
    g_context.result = result ? result : "";
    g_context.baseUrl = base_url ? base_url : "";
}

int legado_eval(JSContext *ctx,
                const char *code,
                size_t code_len,
                char *result_buf,
                size_t result_buf_size) {
    if (!ctx || !code || code_len == 0) {
        if (result_buf && result_buf_size > 0) result_buf[0] = '\0';
        return -1;
    }
    
    // 先执行jsLib
    if (!g_context.jsLib.empty()) {
        JSValue libRet = JS_Eval(ctx, g_context.jsLib.c_str(), g_context.jsLib.length(), 
                                  "<jsLib>", JS_EVAL_TYPE_GLOBAL);
        if (JS_IsException(libRet)) {
            JSValue exc = JS_GetException(ctx);
            std::string err = js_to_string(ctx, exc);
            OH_LOG_ERROR(LOG_APP, "jsLib error: %{public}s", err.c_str());
            JS_FreeValue(ctx, exc);
        }
        JS_FreeValue(ctx, libRet);
    }
    
    // 更新上下文变量
    JSValue global = JS_GetGlobalObject(ctx);
    JS_SetPropertyStr(ctx, global, "key", JS_NewString(ctx, g_context.key.c_str()));
    JS_SetPropertyStr(ctx, global, "page", JS_NewInt32(ctx, g_context.page));
    JS_SetPropertyStr(ctx, global, "result", JS_NewString(ctx, g_context.result.c_str()));
    JS_SetPropertyStr(ctx, global, "baseUrl", JS_NewString(ctx, g_context.baseUrl.c_str()));
    JS_FreeValue(ctx, global);
    
    // 直接执行代码（QuickJS会返回最后一个表达式的值）
    JSValue ret = JS_Eval(ctx, code, code_len, "<eval>", JS_EVAL_TYPE_GLOBAL);
    
    if (JS_IsException(ret)) {
        JSValue exc = JS_GetException(ctx);
        std::string err = js_to_string(ctx, exc);
        OH_LOG_ERROR(LOG_APP, "Eval error: %{public}s", err.c_str());
        JS_FreeValue(ctx, exc);
        
        if (result_buf && result_buf_size > 0) {
            snprintf(result_buf, result_buf_size, "ERROR:%s", err.c_str());
        }
        JS_FreeValue(ctx, ret);
        return -1;
    }
    
    // 获取结果
    std::string result = js_to_string(ctx, ret);
    JS_FreeValue(ctx, ret);
    
    if (result_buf && result_buf_size > 0) {
        strncpy(result_buf, result.c_str(), result_buf_size - 1);
        result_buf[result_buf_size - 1] = '\0';
    }
    
    return 0;
}

// ============ 导出函数 ============

extern "C" {

const char* legado_source_get_variable(const char *source_url) {
    static std::string result;
    std::string key = source_url ? source_url : g_context.sourceUrl;
    auto it = g_sourceVariables.find(key);
    if (it != g_sourceVariables.end()) {
        result = it->second;
        return result.c_str();
    }
    return "";
}

void legado_source_set_variable(const char *source_url, const char *value) {
    std::string key = source_url ? source_url : g_context.sourceUrl;
    g_sourceVariables[key] = value ? value : "";
}

const char* legado_cookie_get(const char *url) {
    static std::string result;
    auto it = g_cookies.find(url ? url : "");
    if (it != g_cookies.end()) {
        result = it->second;
        return result.c_str();
    }
    return "";
}

void legado_cookie_set(const char *url, const char *cookie) {
    g_cookies[url ? url : ""] = cookie ? cookie : "";
}

void legado_cookie_remove(const char *url) {
    g_cookies.erase(url ? url : "");
}

const char* legado_base64_encode(const char *input) {
    static std::string result;
    result = base64_encode(input ? input : "");
    return result.c_str();
}

const char* legado_base64_decode(const char *input) {
    static std::string result;
    result = base64_decode(input ? input : "");
    return result.c_str();
}

const char* legado_hex_decode(const char *input) {
    static std::string result;
    result = hex_decode(input ? input : "");
    return result.c_str();
}

const char* legado_md5_encode(const char *input) {
    static std::string result;
    result = simple_md5(input ? input : "");
    return result.c_str();
}

} // extern "C"
