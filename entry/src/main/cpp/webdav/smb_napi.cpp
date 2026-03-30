/**
 * SMB NAPI Bridge
 * 将原生 libsmb2 客户端暴露给 ArkTS，统一接入现有网络文件夹管理链路
 */

#include <napi/native_api.h>
#include <hilog/log.h>

#include <exception>
#include <memory>
#include <mutex>
#include <string>

#include "smb_client.h"

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3201
#define LOG_TAG "SMBNapi"

static std::unique_ptr<smbnative::SMBClient> g_smbClient = nullptr;
static std::mutex g_smbMutex;

static bool GetOptionalNamedProperty(napi_env env, napi_value obj, const char* name, napi_value* out)
{
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

static std::string GetStringFromNapi(napi_env env, napi_value value)
{
    if (value == nullptr) {
        return "";
    }

    napi_valuetype valueType = napi_undefined;
    napi_typeof(env, value, &valueType);
    if (valueType != napi_string) {
        return "";
    }

    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok || length == 0) {
        return "";
    }

    std::string result(length + 1, '\0');
    size_t copiedLength = 0;
    if (napi_get_value_string_utf8(env, value, &result[0], result.size(), &copiedLength) != napi_ok) {
        return "";
    }
    result.resize(copiedLength);
    return result;
}

static int32_t GetInt32FromNapi(napi_env env, napi_value value)
{
    int32_t result = 0;
    napi_get_value_int32(env, value, &result);
    return result;
}

static bool GetBoolFromNapi(napi_env env, napi_value value)
{
    bool result = false;
    napi_get_value_bool(env, value, &result);
    return result;
}

static napi_value CreateStringNapi(napi_env env, const std::string& value)
{
    napi_value result = nullptr;
    napi_create_string_utf8(env, value.c_str(), value.length(), &result);
    return result;
}

static napi_value CreateBoolNapi(napi_env env, bool value)
{
    napi_value result = nullptr;
    napi_get_boolean(env, value, &result);
    return result;
}

static napi_value CreateInt32Napi(napi_env env, int32_t value)
{
    napi_value result = nullptr;
    napi_create_int32(env, value, &result);
    return result;
}

static napi_value CreateInt64Napi(napi_env env, int64_t value)
{
    napi_value result = nullptr;
    napi_create_int64(env, value, &result);
    return result;
}

static napi_value CreateResultObject(napi_env env, const smbnative::Result& result)
{
    napi_value obj = nullptr;
    napi_create_object(env, &obj);
    napi_set_named_property(env, obj, "success", CreateBoolNapi(env, result.success));
    napi_set_named_property(env, obj, "statusCode", CreateInt32Napi(env, result.statusCode));
    napi_set_named_property(env, obj, "message", CreateStringNapi(env, result.message));
    napi_set_named_property(env, obj, "data", CreateStringNapi(env, result.data));
    return obj;
}

static napi_value CreateFileInfoObject(napi_env env, const smbnative::FileInfo& info)
{
    napi_value obj = nullptr;
    napi_create_object(env, &obj);
    napi_set_named_property(env, obj, "path", CreateStringNapi(env, info.path));
    napi_set_named_property(env, obj, "name", CreateStringNapi(env, info.name));
    napi_set_named_property(env, obj, "size", CreateInt64Napi(env, info.size));
    napi_set_named_property(env, obj, "lastModified", CreateInt64Napi(env, info.lastModified));
    napi_set_named_property(env, obj, "isDirectory", CreateBoolNapi(env, info.isDirectory));
    return obj;
}

static napi_value CreateListResultObject(napi_env env, const smbnative::ListResult& result)
{
    napi_value obj = nullptr;
    napi_create_object(env, &obj);
    napi_set_named_property(env, obj, "success", CreateBoolNapi(env, result.success));
    napi_set_named_property(env, obj, "statusCode", CreateInt32Napi(env, result.statusCode));
    napi_set_named_property(env, obj, "message", CreateStringNapi(env, result.message));

    napi_value filesArray = nullptr;
    napi_create_array_with_length(env, result.files.size(), &filesArray);
    for (size_t index = 0; index < result.files.size(); index++) {
        napi_set_element(env, filesArray, index, CreateFileInfoObject(env, result.files[index]));
    }

    napi_set_named_property(env, obj, "files", filesArray);
    return obj;
}

static napi_value SmbInit(napi_env env, napi_callback_info info)
{
    OH_LOG_INFO(LOG_APP, "开始初始化 SMB 原生客户端");

    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        OH_LOG_ERROR(LOG_APP, "初始化 SMB 原生客户端失败，缺少配置对象");
        return CreateBoolNapi(env, false);
    }

    smbnative::Config config;
    napi_value hostValue = nullptr;
    napi_value shareValue = nullptr;
    napi_value portValue = nullptr;
    napi_value usernameValue = nullptr;
    napi_value passwordValue = nullptr;
    napi_value domainValue = nullptr;
    napi_value workstationValue = nullptr;
    napi_value timeoutValue = nullptr;
    napi_value encryptionValue = nullptr;

    GetOptionalNamedProperty(env, args[0], "host", &hostValue);
    GetOptionalNamedProperty(env, args[0], "shareName", &shareValue);
    GetOptionalNamedProperty(env, args[0], "port", &portValue);
    GetOptionalNamedProperty(env, args[0], "username", &usernameValue);
    GetOptionalNamedProperty(env, args[0], "password", &passwordValue);
    GetOptionalNamedProperty(env, args[0], "domain", &domainValue);
    GetOptionalNamedProperty(env, args[0], "workstation", &workstationValue);
    GetOptionalNamedProperty(env, args[0], "timeoutMs", &timeoutValue);
    GetOptionalNamedProperty(env, args[0], "enableEncryption", &encryptionValue);

    config.host = GetStringFromNapi(env, hostValue);
    config.shareName = GetStringFromNapi(env, shareValue);
    config.username = GetStringFromNapi(env, usernameValue);
    config.password = GetStringFromNapi(env, passwordValue);
    config.domain = GetStringFromNapi(env, domainValue);
    config.workstation = GetStringFromNapi(env, workstationValue);

    napi_valuetype valueType = napi_undefined;
    napi_typeof(env, portValue, &valueType);
    if (valueType == napi_number) {
        config.port = GetInt32FromNapi(env, portValue);
    }

    napi_typeof(env, timeoutValue, &valueType);
    if (valueType == napi_number) {
        config.timeoutMs = GetInt32FromNapi(env, timeoutValue);
    }

    napi_typeof(env, encryptionValue, &valueType);
    if (valueType == napi_boolean) {
        config.enableEncryption = GetBoolFromNapi(env, encryptionValue);
    }

    if (config.host.empty() || config.shareName.empty()) {
        OH_LOG_ERROR(LOG_APP, "初始化 SMB 原生客户端失败，host 或 shareName 为空");
        return CreateBoolNapi(env, false);
    }

    try {
        std::lock_guard<std::mutex> lock(g_smbMutex);
        g_smbClient = std::make_unique<smbnative::SMBClient>(config);
        OH_LOG_INFO(
            LOG_APP,
            "SMB 原生客户端初始化完成，host=%{public}s share=%{public}s",
            config.host.c_str(),
            config.shareName.c_str()
        );
        return CreateBoolNapi(env, true);
    } catch (const std::exception& exception) {
        OH_LOG_ERROR(LOG_APP, "初始化 SMB 原生客户端异常: %{public}s", exception.what());
        return CreateBoolNapi(env, false);
    }
}

static napi_value SmbTestConnection(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::lock_guard<std::mutex> lock(g_smbMutex);
    if (!g_smbClient) {
        smbnative::Result result;
        result.success = false;
        result.message = "SMB 原生客户端未初始化";
        return CreateResultObject(env, result);
    }

    const std::string remotePath = argc >= 1 ? GetStringFromNapi(env, args[0]) : "";
    const smbnative::Result result = g_smbClient->testConnection(remotePath);
    return CreateResultObject(env, result);
}

static napi_value SmbList(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::lock_guard<std::mutex> lock(g_smbMutex);
    if (!g_smbClient) {
        smbnative::ListResult result;
        result.success = false;
        result.message = "SMB 原生客户端未初始化";
        return CreateListResultObject(env, result);
    }

    const std::string remotePath = argc >= 1 ? GetStringFromNapi(env, args[0]) : "";
    const smbnative::ListResult result = g_smbClient->list(remotePath);
    return CreateListResultObject(env, result);
}

static napi_value SmbDownload(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr, nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::lock_guard<std::mutex> lock(g_smbMutex);
    if (!g_smbClient) {
        smbnative::Result result;
        result.success = false;
        result.message = "SMB 原生客户端未初始化";
        return CreateResultObject(env, result);
    }

    if (argc < 2) {
        smbnative::Result result;
        result.success = false;
        result.message = "缺少下载参数";
        return CreateResultObject(env, result);
    }

    const std::string remotePath = GetStringFromNapi(env, args[0]);
    const std::string localPath = GetStringFromNapi(env, args[1]);
    if (localPath.empty()) {
        smbnative::Result result;
        result.success = false;
        result.message = "本地缓存路径不能为空";
        return CreateResultObject(env, result);
    }

    const smbnative::Result result = g_smbClient->downloadFile(remotePath, localPath);
    return CreateResultObject(env, result);
}

static napi_value SmbDestroy(napi_env env, napi_callback_info info)
{
    OH_LOG_INFO(LOG_APP, "销毁 SMB 原生客户端");
    std::lock_guard<std::mutex> lock(g_smbMutex);
    g_smbClient.reset();

    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

void RegisterSMBFunctions(napi_env env, napi_value exports)
{
    napi_property_descriptor smbDesc[] = {
        { "smbInit", nullptr, SmbInit, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "smbTestConnection", nullptr, SmbTestConnection, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "smbList", nullptr, SmbList, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "smbDownload", nullptr, SmbDownload, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "smbDestroy", nullptr, SmbDestroy, nullptr, nullptr, nullptr, napi_default, nullptr },
    };

    napi_define_properties(env, exports, sizeof(smbDesc) / sizeof(smbDesc[0]), smbDesc);
    OH_LOG_INFO(LOG_APP, "SMB 原生接口已注册");
}
