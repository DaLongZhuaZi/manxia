/**
 * QuickJS NAPI Binding - HarmonyOS Native接口
 * 
 * 提供ArkTS调用QuickJS引擎的NAPI接口
 * 这是QuickJS引擎与HarmonyOS应用层的桥梁
 */

#include "napi/native_api.h"
#include "hilog/log.h"
#include "legado_api.h"
#include "quickjs/quickjs.h"
#include <string>
#include <cstring>
#include <mutex>

// 全局QuickJS实例
static JSRuntime *g_runtime = nullptr;
static JSContext *g_context = nullptr;
static std::mutex g_mutex;
static bool g_initialized = false;

// 日志配置
#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3201
#define LOG_TAG "QuickJSNAPI"

// ============ 辅助函数 ============

/**
 * 从napi_value获取字符串
 */
static std::string GetStringFromNapi(napi_env env, napi_value value) {
    size_t strLen = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &strLen);
    
    std::string result(strLen, '\0');
    napi_get_value_string_utf8(env, value, &result[0], strLen + 1, &strLen);
    
    return result;
}

/**
 * 创建napi字符串
 */
static napi_value CreateNapiString(napi_env env, const std::string &str) {
    napi_value result;
    napi_create_string_utf8(env, str.c_str(), str.length(), &result);
    return result;
}

/**
 * 创建napi布尔值
 */
static napi_value CreateNapiBool(napi_env env, bool value) {
    napi_value result;
    napi_get_boolean(env, value, &result);
    return result;
}

// ============ NAPI导出函数 ============

/**
 * 初始化QuickJS引擎
 * 
 * @returns {boolean} 是否成功
 */
static napi_value Init(napi_env env, napi_callback_info info) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    if (g_initialized) {
        OH_LOG_INFO(LOG_APP, "QuickJS already initialized");
        return CreateNapiBool(env, true);
    }
    
    OH_LOG_INFO(LOG_APP, "Initializing QuickJS engine");
    
    g_runtime = JS_NewRuntime();
    if (!g_runtime) {
        OH_LOG_ERROR(LOG_APP, "Failed to create QuickJS runtime");
        return CreateNapiBool(env, false);
    }
    
    JS_SetMemoryLimit(g_runtime, 64 * 1024 * 1024);
    
    g_context = JS_NewContext(g_runtime);
    if (!g_context) {
        OH_LOG_ERROR(LOG_APP, "Failed to create QuickJS context");
        JS_FreeRuntime(g_runtime);
        g_runtime = nullptr;
        return CreateNapiBool(env, false);
    }
    
    if (legado_api_init(g_context) != 0) {
        OH_LOG_ERROR(LOG_APP, "Failed to initialize Legado API");
        JS_FreeContext(g_context);
        JS_FreeRuntime(g_runtime);
        g_context = nullptr;
        g_runtime = nullptr;
        return CreateNapiBool(env, false);
    }
    
    g_initialized = true;
    OH_LOG_INFO(LOG_APP, "QuickJS engine initialized successfully");
    
    return CreateNapiBool(env, true);
}

/**
 * 销毁QuickJS引擎
 * 
 * @returns {boolean} 是否成功
 */
static napi_value Destroy(napi_env env, napi_callback_info info) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    if (!g_initialized) {
        return CreateNapiBool(env, true);
    }
    
    OH_LOG_INFO(LOG_APP, "Destroying QuickJS engine");
    
    if (g_context) {
        legado_api_cleanup(g_context);
        JS_FreeContext(g_context);
        g_context = nullptr;
    }
    
    if (g_runtime) {
        JS_FreeRuntime(g_runtime);
        g_runtime = nullptr;
    }
    
    g_initialized = false;
    
    return CreateNapiBool(env, true);
}

/**
 * 设置书源信息
 * 
 * @param {string} sourceUrl - 书源URL
 * @param {string} sourceName - 书源名称
 * @param {string} jsLib - JS库代码
 * @returns {boolean} 是否成功
 */
static napi_value SetSourceInfo(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    
    if (argc < 3) {
        OH_LOG_ERROR(LOG_APP, "SetSourceInfo: invalid arguments");
        return CreateNapiBool(env, false);
    }
    
    std::string sourceUrl = GetStringFromNapi(env, argv[0]);
    std::string sourceName = GetStringFromNapi(env, argv[1]);
    std::string jsLib = GetStringFromNapi(env, argv[2]);
    
    legado_set_source_info(g_context, sourceUrl.c_str(), sourceName.c_str(), jsLib.c_str());
    
    OH_LOG_DEBUG(LOG_APP, "SetSourceInfo: %{public}s (jsLib: %{public}zu bytes)", 
                 sourceName.c_str(), jsLib.length());
    
    return CreateNapiBool(env, true);
}

/**
 * 执行JavaScript代码
 * 
 * @param {string} code - JS代码
 * @param {string} key - 搜索关键字
 * @param {number} page - 页码
 * @param {string} result - 上一步结果
 * @param {string} baseUrl - 基础URL
 * @returns {object} { success: boolean, result: string, error?: string }
 */
static napi_value Execute(napi_env env, napi_callback_info info) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    size_t argc = 5;
    napi_value argv[5];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    
    // 获取参数
    std::string code = argc > 0 ? GetStringFromNapi(env, argv[0]) : "";
    std::string key = argc > 1 ? GetStringFromNapi(env, argv[1]) : "";
    int32_t page = 1;
    if (argc > 2) {
        napi_get_value_int32(env, argv[2], &page);
    }
    std::string result = argc > 3 ? GetStringFromNapi(env, argv[3]) : "";
    std::string baseUrl = argc > 4 ? GetStringFromNapi(env, argv[4]) : "";
    
    // 检查引擎是否初始化
    if (!g_initialized || !g_context) {
        napi_value returnObj;
        napi_create_object(env, &returnObj);
        napi_value successVal;
        napi_get_boolean(env, false, &successVal);
        napi_set_named_property(env, returnObj, "success", successVal);
        napi_value errorVal;
        napi_create_string_utf8(env, "QuickJS not initialized", NAPI_AUTO_LENGTH, &errorVal);
        napi_set_named_property(env, returnObj, "error", errorVal);
        napi_value resultVal;
        napi_create_string_utf8(env, "", 0, &resultVal);
        napi_set_named_property(env, returnObj, "result", resultVal);
        return returnObj;
    }
    
    // 设置上下文
    legado_set_context(g_context, key.c_str(), page, result.c_str(), baseUrl.c_str());
    
    // 执行代码
    char resultBuf[65536] = {0};  // 64KB结果缓冲区
    int ret = legado_eval(g_context, code.c_str(), code.length(), resultBuf, sizeof(resultBuf));
    
    // 创建返回对象
    napi_value returnObj;
    napi_create_object(env, &returnObj);
    
    napi_value successVal;
    napi_get_boolean(env, ret == 0, &successVal);
    napi_set_named_property(env, returnObj, "success", successVal);
    
    napi_value resultVal;
    napi_create_string_utf8(env, resultBuf, strlen(resultBuf), &resultVal);
    napi_set_named_property(env, returnObj, "result", resultVal);
    
    if (ret != 0) {
        napi_value errorVal;
        napi_create_string_utf8(env, "Execution failed", NAPI_AUTO_LENGTH, &errorVal);
        napi_set_named_property(env, returnObj, "error", errorVal);
    }
    
    return returnObj;
}

/**
 * 获取书源变量
 * 
 * @param {string} sourceUrl - 书源URL（可选）
 * @returns {string} 变量值
 */
static napi_value GetSourceVariable(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    
    std::string sourceUrl = argc > 0 ? GetStringFromNapi(env, argv[0]) : "";
    const char *value = legado_source_get_variable(sourceUrl.empty() ? nullptr : sourceUrl.c_str());
    
    return CreateNapiString(env, value ? value : "");
}

/**
 * 设置书源变量
 * 
 * @param {string} sourceUrl - 书源URL
 * @param {string} value - 变量值
 * @returns {boolean} 是否成功
 */
static napi_value SetSourceVariable(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    
    if (argc < 2) {
        return CreateNapiBool(env, false);
    }
    
    std::string sourceUrl = GetStringFromNapi(env, argv[0]);
    std::string value = GetStringFromNapi(env, argv[1]);
    
    legado_source_set_variable(sourceUrl.c_str(), value.c_str());
    
    return CreateNapiBool(env, true);
}

/**
 * 获取Cookie
 * 
 * @param {string} url - URL
 * @returns {string} Cookie值
 */
static napi_value GetCookie(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    
    std::string url = argc > 0 ? GetStringFromNapi(env, argv[0]) : "";
    const char *cookie = legado_cookie_get(url.c_str());
    
    return CreateNapiString(env, cookie ? cookie : "");
}

/**
 * 设置Cookie
 * 
 * @param {string} url - URL
 * @param {string} cookie - Cookie值
 * @returns {boolean} 是否成功
 */
static napi_value SetCookie(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    
    if (argc < 2) {
        return CreateNapiBool(env, false);
    }
    
    std::string url = GetStringFromNapi(env, argv[0]);
    std::string cookie = GetStringFromNapi(env, argv[1]);
    
    legado_cookie_set(url.c_str(), cookie.c_str());
    
    return CreateNapiBool(env, true);
}

/**
 * Base64编码
 * 
 * @param {string} input - 输入字符串
 * @returns {string} 编码结果
 */
static napi_value Base64Encode(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    
    std::string input = argc > 0 ? GetStringFromNapi(env, argv[0]) : "";
    const char *result = legado_base64_encode(input.c_str());
    
    return CreateNapiString(env, result ? result : "");
}

/**
 * Base64解码
 * 
 * @param {string} input - 输入字符串
 * @returns {string} 解码结果
 */
static napi_value Base64Decode(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    
    std::string input = argc > 0 ? GetStringFromNapi(env, argv[0]) : "";
    const char *result = legado_base64_decode(input.c_str());
    
    return CreateNapiString(env, result ? result : "");
}

/**
 * 十六进制解码
 * 
 * @param {string} input - 输入字符串
 * @returns {string} 解码结果
 */
static napi_value HexDecode(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    
    std::string input = argc > 0 ? GetStringFromNapi(env, argv[0]) : "";
    const char *result = legado_hex_decode(input.c_str());
    
    return CreateNapiString(env, result ? result : "");
}

/**
 * 获取引擎版本信息
 * 
 * @returns {string} 版本信息
 */
static napi_value GetVersion(napi_env env, napi_callback_info info) {
    return CreateNapiString(env, "QuickJS 2024-01-13 (Legado Compatible)");
}

// ============ 模块注册 ============

/**
 * 模块初始化
 */
static napi_value RegisterModule(napi_env env, napi_value exports) {
    OH_LOG_INFO(LOG_APP, "Registering QuickJS NAPI module");
    
    // 定义导出的函数
    napi_property_descriptor desc[] = {
        {"init", nullptr, Init, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"destroy", nullptr, Destroy, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setSourceInfo", nullptr, SetSourceInfo, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"execute", nullptr, Execute, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getSourceVariable", nullptr, GetSourceVariable, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setSourceVariable", nullptr, SetSourceVariable, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getCookie", nullptr, GetCookie, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setCookie", nullptr, SetCookie, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"base64Encode", nullptr, Base64Encode, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"base64Decode", nullptr, Base64Decode, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"hexDecode", nullptr, HexDecode, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getVersion", nullptr, GetVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    
    return exports;
}

// 模块描述
static napi_module quickjsModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = RegisterModule,
    .nm_modname = "quickjs_engine",
    .nm_priv = nullptr,
    .reserved = {0},
};

// 模块注册入口
extern "C" __attribute__((constructor)) void RegisterQuickJSModule(void) {
    napi_module_register(&quickjsModule);
}
