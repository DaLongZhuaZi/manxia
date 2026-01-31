/**
 * FTP NAPI Interface
 * 将FTP C++客户端暴露给ArkTS
 * 
 * 文件路径: entry/src/main/cpp/webdav/ftp_napi.cpp
 */

#include <napi/native_api.h>
#include <hilog/log.h>
#include "ftp_client.h"
#include <memory>
#include <string>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x0000
#define LOG_TAG "FTP_NAPI"

// 全局FTP客户端实例
static std::unique_ptr<ftp::FTPClient> g_ftpClient = nullptr;

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
    
    std::string str(len, '\0');
    napi_get_value_string_utf8(env, value, &str[0], len + 1, &len);
    return str;
}

// 辅助函数：创建napi字符串
static napi_value CreateStringNapi(napi_env env, const std::string& str) {
    napi_value result;
    napi_create_string_utf8(env, str.c_str(), str.length(), &result);
    return result;
}

// 辅助函数：创建napi布尔值
static napi_value CreateBoolNapi(napi_env env, bool value) {
    napi_value result;
    napi_get_boolean(env, value, &result);
    return result;
}

// 辅助函数：创建napi整数
static napi_value CreateIntNapi(napi_env env, int64_t value) {
    napi_value result;
    napi_create_int64(env, value, &result);
    return result;
}

/**
 * 初始化FTP客户端
 * ftpInit(config: FTPConfig): boolean
 */
static napi_value FtpInit(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "FTP Init called");
    
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        OH_LOG_ERROR(LOG_APP, "FTP Init: missing config argument");
        return CreateBoolNapi(env, false);
    }
    
    // 解析配置
    ftp::Config config;
    napi_value value;
    
    // host
    if (napi_get_named_property(env, args[0], "host", &value) == napi_ok) {
        config.host = GetStringFromNapi(env, value);
    }
    
    // port
    if (napi_get_named_property(env, args[0], "port", &value) == napi_ok) {
        int32_t port;
        napi_get_value_int32(env, value, &port);
        config.port = port;
    }
    
    // username
    if (napi_get_named_property(env, args[0], "username", &value) == napi_ok) {
        config.username = GetStringFromNapi(env, value);
    }
    
    // password
    if (napi_get_named_property(env, args[0], "password", &value) == napi_ok) {
        config.password = GetStringFromNapi(env, value);
    }
    
    // useFTPS
    if (napi_get_named_property(env, args[0], "useFTPS", &value) == napi_ok) {
        napi_valuetype type;
        napi_typeof(env, value, &type);
        if (type == napi_boolean) {
            napi_get_value_bool(env, value, &config.useFTPS);
        }
    }
    
    // passive
    if (napi_get_named_property(env, args[0], "passive", &value) == napi_ok) {
        napi_valuetype type;
        napi_typeof(env, value, &type);
        if (type == napi_boolean) {
            napi_get_value_bool(env, value, &config.passive);
        }
    }
    
    // timeoutMs
    if (napi_get_named_property(env, args[0], "timeoutMs", &value) == napi_ok) {
        napi_valuetype type;
        napi_typeof(env, value, &type);
        if (type == napi_number) {
            int32_t timeout;
            napi_get_value_int32(env, value, &timeout);
            config.timeoutMs = timeout;
        }
    }
    
    OH_LOG_INFO(LOG_APP, "FTP Init: host=%{public}s, port=%{public}d, useFTPS=%{public}d",
                config.host.c_str(), config.port, config.useFTPS);
    
    // 创建客户端
    g_ftpClient = std::make_unique<ftp::FTPClient>(config);
    
    return CreateBoolNapi(env, true);
}

/**
 * 测试FTP连接
 * ftpTestConnection(): FTPResult
 */
static napi_value FtpTestConnection(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "FTP TestConnection called");
    
    napi_value result;
    napi_create_object(env, &result);
    
    if (!g_ftpClient) {
        napi_set_named_property(env, result, "success", CreateBoolNapi(env, false));
        napi_set_named_property(env, result, "message", CreateStringNapi(env, "FTP client not initialized"));
        return result;
    }
    
    auto ftpResult = g_ftpClient->testConnection();
    
    napi_set_named_property(env, result, "success", CreateBoolNapi(env, ftpResult.success));
    napi_set_named_property(env, result, "message", CreateStringNapi(env, ftpResult.message));
    
    return result;
}

/**
 * 获取目录列表
 * ftpList(remotePath: string): FTPListResult
 */
static napi_value FtpList(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "FTP List called");
    
    napi_value result;
    napi_create_object(env, &result);
    
    if (!g_ftpClient) {
        napi_set_named_property(env, result, "success", CreateBoolNapi(env, false));
        napi_set_named_property(env, result, "message", CreateStringNapi(env, "FTP client not initialized"));
        napi_value emptyArray;
        napi_create_array(env, &emptyArray);
        napi_set_named_property(env, result, "files", emptyArray);
        return result;
    }
    
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    std::string remotePath = "/";
    if (argc >= 1) {
        remotePath = GetStringFromNapi(env, args[0]);
    }
    
    auto listResult = g_ftpClient->list(remotePath);
    
    napi_set_named_property(env, result, "success", CreateBoolNapi(env, listResult.success));
    napi_set_named_property(env, result, "message", CreateStringNapi(env, listResult.message));
    
    // 创建文件数组
    napi_value filesArray;
    napi_create_array_with_length(env, listResult.files.size(), &filesArray);
    
    for (size_t i = 0; i < listResult.files.size(); i++) {
        const auto& file = listResult.files[i];
        napi_value fileObj;
        napi_create_object(env, &fileObj);
        
        napi_set_named_property(env, fileObj, "name", CreateStringNapi(env, file.name));
        napi_set_named_property(env, fileObj, "path", CreateStringNapi(env, file.path));
        napi_set_named_property(env, fileObj, "size", CreateIntNapi(env, file.size));
        napi_set_named_property(env, fileObj, "isDirectory", CreateBoolNapi(env, file.isDirectory));
        napi_set_named_property(env, fileObj, "lastModified", CreateIntNapi(env, file.lastModified));
        napi_set_named_property(env, fileObj, "permissions", CreateStringNapi(env, file.permissions));
        
        napi_set_element(env, filesArray, i, fileObj);
    }
    
    napi_set_named_property(env, result, "files", filesArray);
    
    return result;
}

/**
 * 上传文件
 * ftpUpload(localPath: string, remotePath: string): FTPResult
 */
static napi_value FtpUpload(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "FTP Upload called");
    
    napi_value result;
    napi_create_object(env, &result);
    
    if (!g_ftpClient) {
        napi_set_named_property(env, result, "success", CreateBoolNapi(env, false));
        napi_set_named_property(env, result, "message", CreateStringNapi(env, "FTP client not initialized"));
        return result;
    }
    
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 2) {
        napi_set_named_property(env, result, "success", CreateBoolNapi(env, false));
        napi_set_named_property(env, result, "message", CreateStringNapi(env, "Missing arguments"));
        return result;
    }
    
    std::string localPath = GetStringFromNapi(env, args[0]);
    std::string remotePath = GetStringFromNapi(env, args[1]);
    
    auto ftpResult = g_ftpClient->uploadFile(localPath, remotePath);
    
    napi_set_named_property(env, result, "success", CreateBoolNapi(env, ftpResult.success));
    napi_set_named_property(env, result, "message", CreateStringNapi(env, ftpResult.message));
    
    return result;
}

/**
 * 下载文件
 * ftpDownload(remotePath: string, localPath: string): FTPResult
 */
static napi_value FtpDownload(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "FTP Download called");
    
    napi_value result;
    napi_create_object(env, &result);
    
    if (!g_ftpClient) {
        napi_set_named_property(env, result, "success", CreateBoolNapi(env, false));
        napi_set_named_property(env, result, "message", CreateStringNapi(env, "FTP client not initialized"));
        return result;
    }
    
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 2) {
        napi_set_named_property(env, result, "success", CreateBoolNapi(env, false));
        napi_set_named_property(env, result, "message", CreateStringNapi(env, "Missing arguments"));
        return result;
    }
    
    std::string remotePath = GetStringFromNapi(env, args[0]);
    std::string localPath = GetStringFromNapi(env, args[1]);
    
    auto ftpResult = g_ftpClient->downloadFile(remotePath, localPath);
    
    napi_set_named_property(env, result, "success", CreateBoolNapi(env, ftpResult.success));
    napi_set_named_property(env, result, "message", CreateStringNapi(env, ftpResult.message));
    
    return result;
}

/**
 * 删除文件
 * ftpDelete(remotePath: string): FTPResult
 */
static napi_value FtpDelete(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "FTP Delete called");
    
    napi_value result;
    napi_create_object(env, &result);
    
    if (!g_ftpClient) {
        napi_set_named_property(env, result, "success", CreateBoolNapi(env, false));
        napi_set_named_property(env, result, "message", CreateStringNapi(env, "FTP client not initialized"));
        return result;
    }
    
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        napi_set_named_property(env, result, "success", CreateBoolNapi(env, false));
        napi_set_named_property(env, result, "message", CreateStringNapi(env, "Missing remotePath"));
        return result;
    }
    
    std::string remotePath = GetStringFromNapi(env, args[0]);
    auto ftpResult = g_ftpClient->deleteFile(remotePath);
    
    napi_set_named_property(env, result, "success", CreateBoolNapi(env, ftpResult.success));
    napi_set_named_property(env, result, "message", CreateStringNapi(env, ftpResult.message));
    
    return result;
}

/**
 * 创建目录
 * ftpMkdir(remotePath: string): FTPResult
 */
static napi_value FtpMkdir(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "FTP Mkdir called");
    
    napi_value result;
    napi_create_object(env, &result);
    
    if (!g_ftpClient) {
        napi_set_named_property(env, result, "success", CreateBoolNapi(env, false));
        napi_set_named_property(env, result, "message", CreateStringNapi(env, "FTP client not initialized"));
        return result;
    }
    
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        napi_set_named_property(env, result, "success", CreateBoolNapi(env, false));
        napi_set_named_property(env, result, "message", CreateStringNapi(env, "Missing remotePath"));
        return result;
    }
    
    std::string remotePath = GetStringFromNapi(env, args[0]);
    auto ftpResult = g_ftpClient->mkdir(remotePath);
    
    napi_set_named_property(env, result, "success", CreateBoolNapi(env, ftpResult.success));
    napi_set_named_property(env, result, "message", CreateStringNapi(env, ftpResult.message));
    
    return result;
}

/**
 * 删除目录
 * ftpRmdir(remotePath: string): FTPResult
 */
static napi_value FtpRmdir(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "FTP Rmdir called");
    
    napi_value result;
    napi_create_object(env, &result);
    
    if (!g_ftpClient) {
        napi_set_named_property(env, result, "success", CreateBoolNapi(env, false));
        napi_set_named_property(env, result, "message", CreateStringNapi(env, "FTP client not initialized"));
        return result;
    }
    
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        napi_set_named_property(env, result, "success", CreateBoolNapi(env, false));
        napi_set_named_property(env, result, "message", CreateStringNapi(env, "Missing remotePath"));
        return result;
    }
    
    std::string remotePath = GetStringFromNapi(env, args[0]);
    auto ftpResult = g_ftpClient->rmdir(remotePath);
    
    napi_set_named_property(env, result, "success", CreateBoolNapi(env, ftpResult.success));
    napi_set_named_property(env, result, "message", CreateStringNapi(env, ftpResult.message));
    
    return result;
}

/**
 * 销毁FTP客户端
 * ftpDestroy(): void
 */
static napi_value FtpDestroy(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "FTP Destroy called");
    g_ftpClient.reset();
    
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

// 导出FTP函数到模块
void RegisterFTPFunctions(napi_env env, napi_value exports) {
    napi_property_descriptor ftpDesc[] = {
        { "ftpInit", nullptr, FtpInit, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "ftpTestConnection", nullptr, FtpTestConnection, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "ftpList", nullptr, FtpList, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "ftpUpload", nullptr, FtpUpload, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "ftpDownload", nullptr, FtpDownload, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "ftpDelete", nullptr, FtpDelete, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "ftpMkdir", nullptr, FtpMkdir, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "ftpRmdir", nullptr, FtpRmdir, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "ftpDestroy", nullptr, FtpDestroy, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    
    napi_define_properties(env, exports, sizeof(ftpDesc) / sizeof(ftpDesc[0]), ftpDesc);
    OH_LOG_INFO(LOG_APP, "FTP functions registered");
}
