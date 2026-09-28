/**
 * JSVM Engine - HarmonyOS NEXT Native JavaScript Engine
 * 
 * 基于JSVM-API实现的JavaScript执行引擎，用于执行Legado书源的JS规则
 * 无需JIT权限，使用解释器模式执行
 */

#include "napi/native_api.h"
#include "hilog/log.h"
#include "ark_runtime/jsvm.h"
#include <string>
#include <map>
#include <mutex>
#include <cstring>

// 日志配置
#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3200
#define LOG_TAG "JSVMEngine"

// 最大虚拟机实例数
#define MAX_VM_COUNT 10

// 全局变量
static bool g_jsvmInitialized = false;
static std::mutex g_mutex;

// 虚拟机实例管理
struct JsVmInstance {
    JSVM_VM vm;
    JSVM_Env env;
    JSVM_VMScope vmScope;
    JSVM_EnvScope envScope;
    bool inUse;
};

static JsVmInstance g_vmInstances[MAX_VM_COUNT];
static int g_vmCount = 0;

// 错误检查宏
#define CHECK_JSVM(call) \
    do { \
        JSVM_Status status = (call); \
        if (status != JSVM_OK) { \
            OH_LOG_ERROR(LOG_APP, "JSVM error at %{public}s:%{public}d, status=%{public}d", \
                __FILE__, __LINE__, status); \
            return status; \
        } \
    } while (0)

#define CHECK_JSVM_RET(call, retVal) \
    do { \
        JSVM_Status status = (call); \
        if (status != JSVM_OK) { \
            const JSVM_ExtendedErrorInfo *info; \
            OH_JSVM_GetLastErrorInfo(env, &info); \
            OH_LOG_ERROR(LOG_APP, "JSVM error: %{public}s", \
                info != nullptr ? info->errorMessage : "unknown"); \
            return retVal; \
        } \
    } while (0)

/**
 * 初始化JSVM引擎
 */
static JSVM_Status InitJsvm() {
    if (g_jsvmInitialized) {
        return JSVM_OK;
    }
    
    JSVM_InitOptions initOptions;
    memset(&initOptions, 0, sizeof(initOptions));
    
    JSVM_Status status = OH_JSVM_Init(&initOptions);
    if (status == JSVM_OK) {
        g_jsvmInitialized = true;
        OH_LOG_INFO(LOG_APP, "JSVM initialized successfully");
    }
    return status;
}

/**
 * 创建一个新的虚拟机实例
 * @return 虚拟机实例ID，失败返回-1
 */
static int CreateVmInstance() {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    // 确保JSVM已初始化
    if (InitJsvm() != JSVM_OK) {
        OH_LOG_ERROR(LOG_APP, "Failed to initialize JSVM");
        return -1;
    }
    
    // 查找空闲槽位
    int slotId = -1;
    for (int i = 0; i < MAX_VM_COUNT; i++) {
        if (!g_vmInstances[i].inUse) {
            slotId = i;
            break;
        }
    }
    
    if (slotId == -1) {
        OH_LOG_ERROR(LOG_APP, "No available VM slot");
        return -1;
    }
    
    JsVmInstance* instance = &g_vmInstances[slotId];
    
    // 创建虚拟机
    JSVM_CreateVMOptions vmOptions;
    memset(&vmOptions, 0, sizeof(vmOptions));
    
    if (OH_JSVM_CreateVM(&vmOptions, &instance->vm) != JSVM_OK) {
        OH_LOG_ERROR(LOG_APP, "Failed to create VM");
        return -1;
    }
    
    // 打开虚拟机作用域
    if (OH_JSVM_OpenVMScope(instance->vm, &instance->vmScope) != JSVM_OK) {
        OH_JSVM_DestroyVM(instance->vm);
        OH_LOG_ERROR(LOG_APP, "Failed to open VM scope");
        return -1;
    }
    
    // 创建环境（不注册额外的属性）
    if (OH_JSVM_CreateEnv(instance->vm, 0, nullptr, &instance->env) != JSVM_OK) {
        OH_JSVM_CloseVMScope(instance->vm, instance->vmScope);
        OH_JSVM_DestroyVM(instance->vm);
        OH_LOG_ERROR(LOG_APP, "Failed to create env");
        return -1;
    }
    
    // 打开环境作用域
    if (OH_JSVM_OpenEnvScope(instance->env, &instance->envScope) != JSVM_OK) {
        OH_JSVM_DestroyEnv(instance->env);
        OH_JSVM_CloseVMScope(instance->vm, instance->vmScope);
        OH_JSVM_DestroyVM(instance->vm);
        OH_LOG_ERROR(LOG_APP, "Failed to open env scope");
        return -1;
    }
    
    instance->inUse = true;
    g_vmCount++;
    
    OH_LOG_INFO(LOG_APP, "Created VM instance %{public}d, total: %{public}d", slotId, g_vmCount);
    return slotId;
}

/**
 * 销毁虚拟机实例
 */
static void DestroyVmInstance(int vmId) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    if (vmId < 0 || vmId >= MAX_VM_COUNT || !g_vmInstances[vmId].inUse) {
        return;
    }
    
    JsVmInstance* instance = &g_vmInstances[vmId];
    
    OH_JSVM_CloseEnvScope(instance->env, instance->envScope);
    OH_JSVM_DestroyEnv(instance->env);
    OH_JSVM_CloseVMScope(instance->vm, instance->vmScope);
    OH_JSVM_DestroyVM(instance->vm);
    
    instance->inUse = false;
    g_vmCount--;
    
    OH_LOG_INFO(LOG_APP, "Destroyed VM instance %{public}d, remaining: %{public}d", vmId, g_vmCount);
}

/**
 * 在指定虚拟机中执行JavaScript代码
 * @param vmId 虚拟机实例ID
 * @param jsCode JavaScript代码
 * @param result 输出结果字符串
 * @return 是否执行成功
 */
static bool ExecuteJs(int vmId, const char* jsCode, std::string& result) {
    if (vmId < 0 || vmId >= MAX_VM_COUNT || !g_vmInstances[vmId].inUse) {
        result = "Invalid VM instance";
        return false;
    }
    
    JsVmInstance* instance = &g_vmInstances[vmId];
    JSVM_Env env = instance->env;
    
    // 打开句柄作用域
    JSVM_HandleScope handleScope;
    if (OH_JSVM_OpenHandleScope(env, &handleScope) != JSVM_OK) {
        result = "Failed to open handle scope";
        return false;
    }
    
    bool success = false;
    
    do {
        // 创建JS字符串
        JSVM_Value jsSource;
        if (OH_JSVM_CreateStringUtf8(env, jsCode, strlen(jsCode), &jsSource) != JSVM_OK) {
            result = "Failed to create JS source string";
            break;
        }
        
        // 编译脚本（eagerCompile=false 使用懒编译，减少开销）
        JSVM_Script script;
        bool cacheRejected = false;
        if (OH_JSVM_CompileScript(env, jsSource, nullptr, 0, false, &cacheRejected, &script) != JSVM_OK) {
            const JSVM_ExtendedErrorInfo *info;
            OH_JSVM_GetLastErrorInfo(env, &info);
            result = "Compile error: ";
            result += (info != nullptr && info->errorMessage != nullptr) ? info->errorMessage : "unknown";
            break;
        }
        
        // 执行脚本
        JSVM_Value jsResult;
        if (OH_JSVM_RunScript(env, script, &jsResult) != JSVM_OK) {
            const JSVM_ExtendedErrorInfo *info;
            OH_JSVM_GetLastErrorInfo(env, &info);
            result = "Runtime error: ";
            result += (info != nullptr && info->errorMessage != nullptr) ? info->errorMessage : "unknown";
            break;
        }
        
        // 获取结果类型
        JSVM_ValueType valueType;
        if (OH_JSVM_Typeof(env, jsResult, &valueType) != JSVM_OK) {
            result = "Failed to get result type";
            break;
        }
        
        // 根据类型转换结果
        switch (valueType) {
            case JSVM_UNDEFINED:
                result = "undefined";
                break;
            case JSVM_NULL:
                result = "null";
                break;
            case JSVM_BOOLEAN: {
                bool boolValue;
                OH_JSVM_GetValueBool(env, jsResult, &boolValue);
                result = boolValue ? "true" : "false";
                break;
            }
            case JSVM_NUMBER: {
                double numValue;
                OH_JSVM_GetValueDouble(env, jsResult, &numValue);
                // 检查是否为整数
                if (numValue == (int64_t)numValue) {
                    result = std::to_string((int64_t)numValue);
                } else {
                    result = std::to_string(numValue);
                }
                break;
            }
            case JSVM_STRING: {
                size_t strLen;
                OH_JSVM_GetValueStringUtf8(env, jsResult, nullptr, 0, &strLen);
                char* strBuf = new char[strLen + 1];
                OH_JSVM_GetValueStringUtf8(env, jsResult, strBuf, strLen + 1, &strLen);
                result = strBuf;
                delete[] strBuf;
                break;
            }
            case JSVM_OBJECT:
            case JSVM_FUNCTION: {
                // 尝试调用JSON.stringify
                JSVM_Value global;
                OH_JSVM_GetGlobal(env, &global);
                
                JSVM_Value jsonStr;
                OH_JSVM_CreateStringUtf8(env, "JSON", JSVM_AUTO_LENGTH, &jsonStr);
                
                JSVM_Value jsonObj;
                if (OH_JSVM_GetProperty(env, global, jsonStr, &jsonObj) == JSVM_OK) {
                    JSVM_Value stringifyStr;
                    OH_JSVM_CreateStringUtf8(env, "stringify", JSVM_AUTO_LENGTH, &stringifyStr);
                    
                    JSVM_Value stringifyFunc;
                    if (OH_JSVM_GetProperty(env, jsonObj, stringifyStr, &stringifyFunc) == JSVM_OK) {
                        JSVM_Value args[] = { jsResult };
                        JSVM_Value jsonResult;
                        if (OH_JSVM_CallFunction(env, jsonObj, stringifyFunc, 1, args, &jsonResult) == JSVM_OK) {
                            size_t jsonLen;
                            OH_JSVM_GetValueStringUtf8(env, jsonResult, nullptr, 0, &jsonLen);
                            char* jsonBuf = new char[jsonLen + 1];
                            OH_JSVM_GetValueStringUtf8(env, jsonResult, jsonBuf, jsonLen + 1, &jsonLen);
                            result = jsonBuf;
                            delete[] jsonBuf;
                        } else {
                            result = "[Object]";
                        }
                    } else {
                        result = "[Object]";
                    }
                } else {
                    result = "[Object]";
                }
                break;
            }
            default:
                result = "[Unknown type]";
                break;
        }
        
        success = true;
    } while (false);
    
    // 关闭句柄作用域
    OH_JSVM_CloseHandleScope(env, handleScope);
    
    return success;
}

/**
 * 在指定虚拟机中设置全局变量
 */
static bool SetGlobalVariable(int vmId, const char* name, const char* value) {
    if (vmId < 0 || vmId >= MAX_VM_COUNT || !g_vmInstances[vmId].inUse) {
        return false;
    }
    
    JsVmInstance* instance = &g_vmInstances[vmId];
    JSVM_Env env = instance->env;
    
    JSVM_HandleScope handleScope;
    if (OH_JSVM_OpenHandleScope(env, &handleScope) != JSVM_OK) {
        return false;
    }
    
    bool success = false;
    
    do {
        JSVM_Value global;
        if (OH_JSVM_GetGlobal(env, &global) != JSVM_OK) break;
        
        JSVM_Value propName;
        if (OH_JSVM_CreateStringUtf8(env, name, strlen(name), &propName) != JSVM_OK) break;
        
        JSVM_Value propValue;
        if (OH_JSVM_CreateStringUtf8(env, value, strlen(value), &propValue) != JSVM_OK) break;
        
        if (OH_JSVM_SetProperty(env, global, propName, propValue) != JSVM_OK) break;
        
        success = true;
    } while (false);
    
    OH_JSVM_CloseHandleScope(env, handleScope);
    return success;
}

/**
 * 在指定虚拟机中设置数字类型全局变量
 */
static bool SetGlobalNumber(int vmId, const char* name, double value) {
    if (vmId < 0 || vmId >= MAX_VM_COUNT || !g_vmInstances[vmId].inUse) {
        return false;
    }
    
    JsVmInstance* instance = &g_vmInstances[vmId];
    JSVM_Env env = instance->env;
    
    JSVM_HandleScope handleScope;
    if (OH_JSVM_OpenHandleScope(env, &handleScope) != JSVM_OK) {
        return false;
    }
    
    bool success = false;
    
    do {
        JSVM_Value global;
        if (OH_JSVM_GetGlobal(env, &global) != JSVM_OK) break;
        
        JSVM_Value propName;
        if (OH_JSVM_CreateStringUtf8(env, name, strlen(name), &propName) != JSVM_OK) break;
        
        JSVM_Value propValue;
        if (OH_JSVM_CreateDouble(env, value, &propValue) != JSVM_OK) break;
        
        if (OH_JSVM_SetProperty(env, global, propName, propValue) != JSVM_OK) break;
        
        success = true;
    } while (false);
    
    OH_JSVM_CloseHandleScope(env, handleScope);
    return success;
}

// ==================== NAPI 接口实现 ====================

/**
 * NAPI: 创建虚拟机实例
 * @return vmId (number)
 */
static napi_value NapiCreateVm(napi_env env, napi_callback_info info) {
    int vmId = CreateVmInstance();
    
    napi_value result;
    napi_create_int32(env, vmId, &result);
    return result;
}

/**
 * NAPI: 销毁虚拟机实例
 * @param vmId (number)
 */
static napi_value NapiDestroyVm(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        napi_throw_error(env, nullptr, "vmId is required");
        return nullptr;
    }
    
    int32_t vmId;
    napi_get_value_int32(env, args[0], &vmId);
    
    DestroyVmInstance(vmId);
    
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

/**
 * NAPI: 执行JavaScript代码
 * @param vmId (number)
 * @param jsCode (string)
 * @return { success: boolean, result: string }
 */
static napi_value NapiExecuteJs(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 2) {
        napi_throw_error(env, nullptr, "vmId and jsCode are required");
        return nullptr;
    }
    
    // 获取vmId
    int32_t vmId;
    napi_get_value_int32(env, args[0], &vmId);
    
    // 获取jsCode
    size_t codeLen;
    napi_get_value_string_utf8(env, args[1], nullptr, 0, &codeLen);
    char* jsCode = new char[codeLen + 1];
    napi_get_value_string_utf8(env, args[1], jsCode, codeLen + 1, &codeLen);
    
    // 执行JS
    std::string resultStr;
    bool success = ExecuteJs(vmId, jsCode, resultStr);
    
    delete[] jsCode;
    
    // 创建返回对象
    napi_value resultObj;
    napi_create_object(env, &resultObj);
    
    napi_value successValue;
    napi_get_boolean(env, success, &successValue);
    napi_set_named_property(env, resultObj, "success", successValue);
    
    napi_value resultValue;
    napi_create_string_utf8(env, resultStr.c_str(), resultStr.length(), &resultValue);
    napi_set_named_property(env, resultObj, "result", resultValue);
    
    return resultObj;
}

/**
 * NAPI: 设置全局字符串变量
 * @param vmId (number)
 * @param name (string)
 * @param value (string)
 * @return boolean
 */
static napi_value NapiSetGlobalString(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 3) {
        napi_throw_error(env, nullptr, "vmId, name and value are required");
        return nullptr;
    }
    
    int32_t vmId;
    napi_get_value_int32(env, args[0], &vmId);
    
    size_t nameLen;
    napi_get_value_string_utf8(env, args[1], nullptr, 0, &nameLen);
    char* name = new char[nameLen + 1];
    napi_get_value_string_utf8(env, args[1], name, nameLen + 1, &nameLen);
    
    size_t valueLen;
    napi_get_value_string_utf8(env, args[2], nullptr, 0, &valueLen);
    char* value = new char[valueLen + 1];
    napi_get_value_string_utf8(env, args[2], value, valueLen + 1, &valueLen);
    
    bool success = SetGlobalVariable(vmId, name, value);
    
    delete[] name;
    delete[] value;
    
    napi_value result;
    napi_get_boolean(env, success, &result);
    return result;
}

/**
 * NAPI: 设置全局数字变量
 * @param vmId (number)
 * @param name (string)
 * @param value (number)
 * @return boolean
 */
static napi_value NapiSetGlobalNumber(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 3) {
        napi_throw_error(env, nullptr, "vmId, name and value are required");
        return nullptr;
    }
    
    int32_t vmId;
    napi_get_value_int32(env, args[0], &vmId);
    
    size_t nameLen;
    napi_get_value_string_utf8(env, args[1], nullptr, 0, &nameLen);
    char* name = new char[nameLen + 1];
    napi_get_value_string_utf8(env, args[1], name, nameLen + 1, &nameLen);
    
    double value;
    napi_get_value_double(env, args[2], &value);
    
    bool success = SetGlobalNumber(vmId, name, value);
    
    delete[] name;
    
    napi_value result;
    napi_get_boolean(env, success, &result);
    return result;
}

/**
 * NAPI: 获取虚拟机数量
 * @return number
 */
static napi_value NapiGetVmCount(napi_env env, napi_callback_info info) {
    napi_value result;
    napi_create_int32(env, g_vmCount, &result);
    return result;
}

// ==================== 模块注册 ====================

static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        { "createVm", nullptr, NapiCreateVm, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "destroyVm", nullptr, NapiDestroyVm, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "executeJs", nullptr, NapiExecuteJs, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setGlobalString", nullptr, NapiSetGlobalString, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setGlobalNumber", nullptr, NapiSetGlobalNumber, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getVmCount", nullptr, NapiGetVmCount, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    
    OH_LOG_INFO(LOG_APP, "JSVMEngine module initialized");
    return exports;
}

EXTERN_C_START
static napi_module jsvmModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "jsvm_engine",
    .nm_priv = nullptr,
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterJsvmModule(void) {
    napi_module_register(&jsvmModule);
}
EXTERN_C_END
