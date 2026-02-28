/**
 * WebDAV NAPI Bridge
 * 将C++ WebDAV客户端暴露给ArkTS
 * 
 * 文件路径: entry/src/main/cpp/webdav/webdav_napi.cpp
 */

#include <napi/native_api.h>
#include <hilog/log.h>
#include "webdav_client.h"
#include <string>
#include <memory>
#include <mutex>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3201
#define LOG_TAG "WebDAVNapi"

// 全局WebDAV客户端实例（简化实现，实际应该使用实例管理）
static std::unique_ptr<webdav::WebDAVClient> g_client = nullptr;
static std::mutex g_clientMutex;

static bool GetOptionalNamedProperty(napi_env env, napi_value obj, const char* name, napi_value* out) {
    bool hasProperty = false;
    if (napi_has_named_property(env, obj, name, &hasProperty) != napi_ok || !hasProperty) {
        napi_get_undefined(env, out);
        return false;
    }
    if (napi_get_named_property(env, obj, name, out) != napi_ok) {
        napi_get_undefined(env, out);
        return false;
    }
    return true;
}

// 辅助函数：从napi_value获取字符串（带类型检查）
static std::string GetStringFromNapi(napi_env env, napi_value value) {
    if (value == nullptr) {
        return "";
    }
    
    napi_valuetype valueType;
    napi_typeof(env, value, &valueType);
    if (valueType != napi_string) {
        return "";
    }
    
    size_t len = 0;
    napi_status status = napi_get_value_string_utf8(env, value, nullptr, 0, &len);
    if (status != napi_ok || len == 0) {
        return "";
    }
    
    std::string result(len, '\0');
    napi_get_value_string_utf8(env, value, &result[0], len + 1, &len);
    return result;
}

// 辅助函数：从napi_value获取整数
static int32_t GetInt32FromNapi(napi_env env, napi_value value) {
    int32_t result = 0;
    napi_get_value_int32(env, value, &result);
    return result;
}

// 辅助函数：从napi_value获取布尔值
static bool GetBoolFromNapi(napi_env env, napi_value value) {
    bool result = false;
    napi_get_value_bool(env, value, &result);
    return result;
}

// 辅助函数：创建字符串napi_value
static napi_value CreateStringNapi(napi_env env, const std::string& str) {
    napi_value result;
    napi_create_string_utf8(env, str.c_str(), str.length(), &result);
    return result;
}

// 辅助函数：创建整数napi_value
static napi_value CreateInt32Napi(napi_env env, int32_t value) {
    napi_value result;
    napi_create_int32(env, value, &result);
    return result;
}

// 辅助函数：创建布尔napi_value
static napi_value CreateBoolNapi(napi_env env, bool value) {
    napi_value result;
    napi_get_boolean(env, value, &result);
    return result;
}

// 辅助函数：创建int64 napi_value
static napi_value CreateInt64Napi(napi_env env, int64_t value) {
    napi_value result;
    napi_create_int64(env, value, &result);
    return result;
}

// 辅助函数：创建Result对象
static napi_value CreateResultObject(napi_env env, const webdav::Result& result) {
    napi_value obj;
    napi_create_object(env, &obj);
    
    napi_value success, statusCode, message, data;
    napi_get_boolean(env, result.success, &success);
    napi_create_int32(env, result.statusCode, &statusCode);
    napi_create_string_utf8(env, result.message.c_str(), result.message.length(), &message);
    napi_create_string_utf8(env, result.data.c_str(), result.data.length(), &data);
    
    napi_set_named_property(env, obj, "success", success);
    napi_set_named_property(env, obj, "statusCode", statusCode);
    napi_set_named_property(env, obj, "message", message);
    napi_set_named_property(env, obj, "data", data);
    
    return obj;
}

// 辅助函数：创建FileInfo对象
static napi_value CreateFileInfoObject(napi_env env, const webdav::FileInfo& info) {
    napi_value obj;
    napi_create_object(env, &obj);
    
    napi_set_named_property(env, obj, "path", CreateStringNapi(env, info.path));
    napi_set_named_property(env, obj, "name", CreateStringNapi(env, info.name));
    napi_set_named_property(env, obj, "size", CreateInt64Napi(env, info.size));
    napi_set_named_property(env, obj, "lastModified", CreateInt64Napi(env, info.lastModified));
    napi_set_named_property(env, obj, "isDirectory", CreateBoolNapi(env, info.isDirectory));
    napi_set_named_property(env, obj, "etag", CreateStringNapi(env, info.etag));
    napi_set_named_property(env, obj, "contentType", CreateStringNapi(env, info.contentType));
    
    return obj;
}

// 辅助函数：创建ListResult对象
static napi_value CreateListResultObject(napi_env env, const webdav::ListResult& result) {
    napi_value obj;
    napi_create_object(env, &obj);
    
    napi_set_named_property(env, obj, "success", CreateBoolNapi(env, result.success));
    napi_set_named_property(env, obj, "statusCode", CreateInt32Napi(env, result.statusCode));
    napi_set_named_property(env, obj, "message", CreateStringNapi(env, result.message));
    
    // 创建文件数组
    napi_value filesArray;
    napi_create_array_with_length(env, result.files.size(), &filesArray);
    
    for (size_t i = 0; i < result.files.size(); i++) {
        napi_set_element(env, filesArray, i, CreateFileInfoObject(env, result.files[i]));
    }
    
    napi_set_named_property(env, obj, "files", filesArray);
    
    return obj;
}

/**
 * 初始化WebDAV客户端
 * init(config: {serverUrl, username, password, basePath, timeoutMs?, verifySSL?}): boolean
 */
static napi_value InitClient(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "WebDAV InitClient called");
    
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        OH_LOG_ERROR(LOG_APP, "WebDAV Init: missing config argument");
        return CreateBoolNapi(env, false);
    }
    
    // 解析配置对象
    webdav::Config config;
    
    napi_value serverUrlVal, usernameVal, passwordVal, basePathVal, timeoutVal, verifySSLVal;
    
    GetOptionalNamedProperty(env, args[0], "serverUrl", &serverUrlVal);
    GetOptionalNamedProperty(env, args[0], "username", &usernameVal);
    GetOptionalNamedProperty(env, args[0], "password", &passwordVal);
    GetOptionalNamedProperty(env, args[0], "basePath", &basePathVal);
    GetOptionalNamedProperty(env, args[0], "timeoutMs", &timeoutVal);
    GetOptionalNamedProperty(env, args[0], "verifySSL", &verifySSLVal);
    
    config.serverUrl = GetStringFromNapi(env, serverUrlVal);
    config.username = GetStringFromNapi(env, usernameVal);
    config.password = GetStringFromNapi(env, passwordVal);
    config.basePath = GetStringFromNapi(env, basePathVal);
    
    napi_valuetype timeoutType;
    napi_typeof(env, timeoutVal, &timeoutType);
    if (timeoutType == napi_number) {
        config.timeoutMs = GetInt32FromNapi(env, timeoutVal);
    }
    
    napi_valuetype verifySSLType;
    napi_typeof(env, verifySSLVal, &verifySSLType);
    if (verifySSLType == napi_boolean) {
        config.verifySSL = GetBoolFromNapi(env, verifySSLVal);
    }
    
    if (config.serverUrl.empty()) {
        OH_LOG_ERROR(LOG_APP, "WebDAV Init failed: serverUrl is empty");
        return CreateBoolNapi(env, false);
    }

    OH_LOG_INFO(LOG_APP, "WebDAV Init: serverUrl=%{public}s, basePath=%{public}s", 
        config.serverUrl.c_str(), config.basePath.c_str());
    
    try {
        std::lock_guard<std::mutex> lock(g_clientMutex);
        g_client = std::make_unique<webdav::WebDAVClient>(config);
        OH_LOG_INFO(LOG_APP, "WebDAV client initialized successfully");
        return CreateBoolNapi(env, true);
    } catch (const std::exception& e) {
        OH_LOG_ERROR(LOG_APP, "WebDAV Init failed: %{public}s", e.what());
        return CreateBoolNapi(env, false);
    }
}

/**
 * 测试连接
 * testConnection(): Result
 */
static napi_value TestConnection(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "WebDAV TestConnection called");
    std::lock_guard<std::mutex> lock(g_clientMutex);
    
    if (!g_client) {
        webdav::Result result;
        result.success = false;
        result.statusCode = 0;
        result.message = "Client not initialized";
        return CreateResultObject(env, result);
    }
    
    webdav::Result result = g_client->testConnection();
    OH_LOG_INFO(LOG_APP, "WebDAV TestConnection result: success=%{public}d, status=%{public}d", 
        result.success, result.statusCode);
    
    return CreateResultObject(env, result);
}

/**
 * 检查文件/目录是否存在
 * exists(remotePath: string): Result
 */
static napi_value Exists(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    std::lock_guard<std::mutex> lock(g_clientMutex);
    if (!g_client || argc < 1) {
        webdav::Result result;
        result.success = false;
        result.statusCode = 0;
        result.message = argc < 1 ? "Missing path argument" : "Client not initialized";
        return CreateResultObject(env, result);
    }
    
    std::string remotePath = GetStringFromNapi(env, args[0]);
    webdav::Result result = g_client->exists(remotePath);
    
    return CreateResultObject(env, result);
}

/**
 * 获取目录内容
 * list(remotePath: string, depth?: number): ListResult
 */
static napi_value List(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "WebDAV List called");
    
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    std::lock_guard<std::mutex> lock(g_clientMutex);
    if (!g_client || argc < 1) {
        webdav::ListResult result;
        result.success = false;
        result.statusCode = 0;
        result.message = argc < 1 ? "Missing path argument" : "Client not initialized";
        return CreateListResultObject(env, result);
    }
    
    std::string remotePath = GetStringFromNapi(env, args[0]);
    int depth = 1;
    
    if (argc >= 2) {
        napi_valuetype depthType;
        napi_typeof(env, args[1], &depthType);
        if (depthType == napi_number) {
            depth = GetInt32FromNapi(env, args[1]);
        }
    }
    
    OH_LOG_INFO(LOG_APP, "WebDAV List: path=%{public}s, depth=%{public}d", remotePath.c_str(), depth);
    
    webdav::ListResult result = g_client->list(remotePath, depth);
    
    OH_LOG_INFO(LOG_APP, "WebDAV List result: success=%{public}d, files=%{public}zu", 
        result.success, result.files.size());
    
    return CreateListResultObject(env, result);
}

/**
 * 创建目录
 * createDirectory(remotePath: string): Result
 */
static napi_value CreateDirectory(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    std::lock_guard<std::mutex> lock(g_clientMutex);
    if (!g_client || argc < 1) {
        webdav::Result result;
        result.success = false;
        result.statusCode = 0;
        result.message = argc < 1 ? "Missing path argument" : "Client not initialized";
        return CreateResultObject(env, result);
    }
    
    std::string remotePath = GetStringFromNapi(env, args[0]);
    webdav::Result result = g_client->createDirectory(remotePath);
    
    return CreateResultObject(env, result);
}

/**
 * 递归创建目录
 * createDirectoryRecursive(remotePath: string): Result
 */
static napi_value CreateDirectoryRecursive(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    std::lock_guard<std::mutex> lock(g_clientMutex);
    if (!g_client || argc < 1) {
        webdav::Result result;
        result.success = false;
        result.statusCode = 0;
        result.message = argc < 1 ? "Missing path argument" : "Client not initialized";
        return CreateResultObject(env, result);
    }
    
    std::string remotePath = GetStringFromNapi(env, args[0]);
    webdav::Result result = g_client->createDirectoryRecursive(remotePath);
    
    return CreateResultObject(env, result);
}

/**
 * 删除文件或目录
 * deleteResource(remotePath: string): Result
 */
static napi_value DeleteResource(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    std::lock_guard<std::mutex> lock(g_clientMutex);
    if (!g_client || argc < 1) {
        webdav::Result result;
        result.success = false;
        result.statusCode = 0;
        result.message = argc < 1 ? "Missing path argument" : "Client not initialized";
        return CreateResultObject(env, result);
    }
    
    std::string remotePath = GetStringFromNapi(env, args[0]);
    webdav::Result result = g_client->deleteResource(remotePath);
    
    return CreateResultObject(env, result);
}

/**
 * 上传文件内容
 * putFileContents(remotePath: string, data: string): Result
 */
static napi_value PutFileContents(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    std::lock_guard<std::mutex> lock(g_clientMutex);
    if (!g_client || argc < 2) {
        webdav::Result result;
        result.success = false;
        result.statusCode = 0;
        result.message = argc < 2 ? "Missing arguments" : "Client not initialized";
        return CreateResultObject(env, result);
    }
    
    std::string remotePath = GetStringFromNapi(env, args[0]);
    std::string data = GetStringFromNapi(env, args[1]);
    
    webdav::Result result = g_client->putFileContents(remotePath, data);
    
    return CreateResultObject(env, result);
}

/**
 * 下载文件内容
 * getFileContents(remotePath: string): Result (data字段包含文件内容)
 */
static napi_value GetFileContents(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    std::lock_guard<std::mutex> lock(g_clientMutex);
    if (!g_client || argc < 1) {
        webdav::Result result;
        result.success = false;
        result.statusCode = 0;
        result.message = argc < 1 ? "Missing path argument" : "Client not initialized";
        return CreateResultObject(env, result);
    }
    
    std::string remotePath = GetStringFromNapi(env, args[0]);
    std::string data;
    webdav::Result result = g_client->getFileContents(remotePath, data);
    result.data = data;
    
    return CreateResultObject(env, result);
}

/**
 * 上传本地文件
 * uploadFile(localPath: string, remotePath: string): Result
 */
static napi_value UploadFile(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    std::lock_guard<std::mutex> lock(g_clientMutex);
    if (!g_client || argc < 2) {
        webdav::Result result;
        result.success = false;
        result.statusCode = 0;
        result.message = argc < 2 ? "Missing arguments" : "Client not initialized";
        return CreateResultObject(env, result);
    }
    
    std::string localPath = GetStringFromNapi(env, args[0]);
    std::string remotePath = GetStringFromNapi(env, args[1]);
    
    OH_LOG_INFO(LOG_APP, "WebDAV UploadFile: %{public}s -> %{public}s", 
        localPath.c_str(), remotePath.c_str());
    
    webdav::Result result = g_client->uploadFile(localPath, remotePath);
    
    return CreateResultObject(env, result);
}

/**
 * 下载文件到本地
 * downloadFile(remotePath: string, localPath: string): Result
 */
static napi_value DownloadFile(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    std::lock_guard<std::mutex> lock(g_clientMutex);
    if (!g_client || argc < 2) {
        webdav::Result result;
        result.success = false;
        result.statusCode = 0;
        result.message = argc < 2 ? "Missing arguments" : "Client not initialized";
        return CreateResultObject(env, result);
    }
    
    std::string remotePath = GetStringFromNapi(env, args[0]);
    std::string localPath = GetStringFromNapi(env, args[1]);
    
    OH_LOG_INFO(LOG_APP, "WebDAV DownloadFile: %{public}s -> %{public}s", 
        remotePath.c_str(), localPath.c_str());
    
    webdav::Result result = g_client->downloadFile(remotePath, localPath);
    
    return CreateResultObject(env, result);
}

/**
 * 复制文件
 * copyFile(sourcePath: string, destPath: string, overwrite?: boolean): Result
 */
static napi_value CopyFile(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    std::lock_guard<std::mutex> lock(g_clientMutex);
    if (!g_client || argc < 2) {
        webdav::Result result;
        result.success = false;
        result.statusCode = 0;
        result.message = argc < 2 ? "Missing arguments" : "Client not initialized";
        return CreateResultObject(env, result);
    }
    
    std::string sourcePath = GetStringFromNapi(env, args[0]);
    std::string destPath = GetStringFromNapi(env, args[1]);
    bool overwrite = true;
    
    if (argc >= 3) {
        napi_valuetype overwriteType;
        napi_typeof(env, args[2], &overwriteType);
        if (overwriteType == napi_boolean) {
            overwrite = GetBoolFromNapi(env, args[2]);
        }
    }
    
    webdav::Result result = g_client->copyFile(sourcePath, destPath, overwrite);
    
    return CreateResultObject(env, result);
}

/**
 * 移动文件
 * moveFile(sourcePath: string, destPath: string, overwrite?: boolean): Result
 */
static napi_value MoveFile(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    std::lock_guard<std::mutex> lock(g_clientMutex);
    if (!g_client || argc < 2) {
        webdav::Result result;
        result.success = false;
        result.statusCode = 0;
        result.message = argc < 2 ? "Missing arguments" : "Client not initialized";
        return CreateResultObject(env, result);
    }
    
    std::string sourcePath = GetStringFromNapi(env, args[0]);
    std::string destPath = GetStringFromNapi(env, args[1]);
    bool overwrite = true;
    
    if (argc >= 3) {
        napi_valuetype overwriteType;
        napi_typeof(env, args[2], &overwriteType);
        if (overwriteType == napi_boolean) {
            overwrite = GetBoolFromNapi(env, args[2]);
        }
    }
    
    webdav::Result result = g_client->moveFile(sourcePath, destPath, overwrite);
    
    return CreateResultObject(env, result);
}

/**
 * 获取磁盘配额
 * getQuota(): {success, usedBytes, availableBytes, message}
 */
static napi_value GetQuota(napi_env env, napi_callback_info info) {
    std::lock_guard<std::mutex> lock(g_clientMutex);
    if (!g_client) {
        napi_value obj;
        napi_create_object(env, &obj);
        napi_set_named_property(env, obj, "success", CreateBoolNapi(env, false));
        napi_set_named_property(env, obj, "message", CreateStringNapi(env, "Client not initialized"));
        return obj;
    }
    
    int64_t usedBytes = 0, availableBytes = 0;
    webdav::Result result = g_client->getQuota(usedBytes, availableBytes);
    
    napi_value obj;
    napi_create_object(env, &obj);
    napi_set_named_property(env, obj, "success", CreateBoolNapi(env, result.success));
    napi_set_named_property(env, obj, "statusCode", CreateInt32Napi(env, result.statusCode));
    napi_set_named_property(env, obj, "message", CreateStringNapi(env, result.message));
    napi_set_named_property(env, obj, "usedBytes", CreateInt64Napi(env, usedBytes));
    napi_set_named_property(env, obj, "availableBytes", CreateInt64Napi(env, availableBytes));
    
    return obj;
}

/**
 * 销毁客户端
 * destroy(): void
 */
static napi_value Destroy(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "WebDAV Destroy called");
    std::lock_guard<std::mutex> lock(g_clientMutex);
    g_client.reset();
    
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

// 声明FTP函数注册（在ftp_napi.cpp中定义）
extern void RegisterFTPFunctions(napi_env env, napi_value exports);

// 模块初始化
EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    OH_LOG_INFO(LOG_APP, "WebDAV Native module initializing");
    
    // WebDAV函数
    napi_property_descriptor desc[] = {
        { "init", nullptr, InitClient, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "testConnection", nullptr, TestConnection, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "exists", nullptr, Exists, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "list", nullptr, List, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "createDirectory", nullptr, CreateDirectory, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "createDirectoryRecursive", nullptr, CreateDirectoryRecursive, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "deleteResource", nullptr, DeleteResource, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "putFileContents", nullptr, PutFileContents, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getFileContents", nullptr, GetFileContents, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "uploadFile", nullptr, UploadFile, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "downloadFile", nullptr, DownloadFile, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "copyFile", nullptr, CopyFile, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "moveFile", nullptr, MoveFile, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getQuota", nullptr, GetQuota, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "destroy", nullptr, Destroy, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    
    // 注册FTP函数
    RegisterFTPFunctions(env, exports);
    
    OH_LOG_INFO(LOG_APP, "WebDAV/FTP Native module initialized");
    return exports;
}
EXTERN_C_END

// 模块描述
static napi_module webdavModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "webdav_native",
    .nm_priv = nullptr,
    .reserved = { 0 },
};

// 模块注册
extern "C" __attribute__((constructor)) void RegisterWebDAVModule(void) {
    napi_module_register(&webdavModule);
}
