/**
 * Network Scanner NAPI Bridge
 * Exposes scanStart, scanStop, scanIsRunning, smbEnumShares to ArkTS
 */

#include <napi/native_api.h>
#include <hilog/log.h>

#include <atomic>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "network_scanner.h"

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3201
#define LOG_TAG "ScannerNapi"

// ---- Shared scanner instance ----
static std::unique_ptr<netscan::NetworkScanner> g_scanner;
static std::mutex g_scannerMutex;

static netscan::NetworkScanner* GetScanner()
{
    std::lock_guard<std::mutex> lock(g_scannerMutex);
    if (!g_scanner) {
        g_scanner = std::make_unique<netscan::NetworkScanner>();
    }
    return g_scanner.get();
}

// ---- NAPI helpers ----

static std::string GetStringFromNapi(napi_env env, napi_value value)
{
    if (value == nullptr) return "";
    napi_valuetype t = napi_undefined;
    napi_typeof(env, value, &t);
    if (t != napi_string) return "";
    size_t len = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &len) != napi_ok || len == 0) return "";
    std::string result(len + 1, '\0');
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, value, &result[0], result.size(), &copied) != napi_ok) return "";
    result.resize(copied);
    return result;
}

static int32_t GetInt32FromNapi(napi_env env, napi_value value)
{
    int32_t r = 0;
    napi_get_value_int32(env, value, &r);
    return r;
}

static bool GetBoolFromNapi(napi_env env, napi_value value)
{
    bool r = false;
    napi_get_value_bool(env, value, &r);
    return r;
}

static napi_value CreateStringNapi(napi_env env, const std::string& v)
{
    napi_value r = nullptr;
    napi_create_string_utf8(env, v.c_str(), v.length(), &r);
    return r;
}

static napi_value CreateBoolNapi(napi_env env, bool v)
{
    napi_value r = nullptr;
    napi_get_boolean(env, v, &r);
    return r;
}

static napi_value CreateInt32Napi(napi_env env, int32_t v)
{
    napi_value r = nullptr;
    napi_create_int32(env, v, &r);
    return r;
}

static bool GetOptionalNamedProperty(napi_env env, napi_value obj, const char* name, napi_value* out)
{
    bool has = false;
    if (napi_has_named_property(env, obj, name, &has) != napi_ok || !has) {
        napi_get_undefined(env, out);
        return false;
    }
    if (napi_get_named_property(env, obj, name, out) != napi_ok) {
        napi_get_undefined(env, out);
        return false;
    }
    return true;
}

// ---- Threadsafe function context ----

struct TsfnContext {
    napi_env env = nullptr;
    napi_threadsafe_function tsfn = nullptr;
};

struct ProgressData {
    int scanned;
    int total;
    std::string currentIP;
};

struct HostFoundData {
    netscan::DiscoveredHost host;
};

struct CompleteData {
    bool cancelled;
};

static void ProgressCallJs(napi_env env, napi_value jsCb, void* context, void* data)
{
    if (env == nullptr || jsCb == nullptr || data == nullptr) {
        delete static_cast<ProgressData*>(data);
        return;
    }
    auto* d = static_cast<ProgressData*>(data);

    napi_value argv[3] = {};
    napi_create_int32(env, d->scanned, &argv[0]);
    napi_create_int32(env, d->total, &argv[1]);
    napi_create_string_utf8(env, d->currentIP.c_str(), d->currentIP.length(), &argv[2]);

    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    napi_call_function(env, undefined, jsCb, 3, argv, nullptr);

    delete d;
}

static void HostFoundCallJs(napi_env env, napi_value jsCb, void* context, void* data)
{
    if (env == nullptr || jsCb == nullptr || data == nullptr) {
        delete static_cast<HostFoundData*>(data);
        return;
    }
    auto* d = static_cast<HostFoundData*>(data);

    napi_value hostObj = nullptr;
    napi_create_object(env, &hostObj);

    napi_set_named_property(env, hostObj, "ip", CreateStringNapi(env, d->host.ip));
    napi_set_named_property(env, hostObj, "hostname", CreateStringNapi(env, d->host.hostname));

    // protocols array (for backward compatibility)
    napi_value protoArr = nullptr;
    napi_create_array_with_length(env, d->host.protocols.size(), &protoArr);
    for (size_t i = 0; i < d->host.protocols.size(); i++) {
        napi_set_element(env, protoArr, i,
            CreateInt32Napi(env, static_cast<int32_t>(d->host.protocols[i])));
    }
    napi_set_named_property(env, hostObj, "protocols", protoArr);

    // protocolPorts array: [{protocol: number, port: number}, ...]
    napi_value protoPortsArr = nullptr;
    napi_create_array_with_length(env, d->host.protocolPorts.size(), &protoPortsArr);
    for (size_t i = 0; i < d->host.protocolPorts.size(); i++) {
        napi_value ppObj = nullptr;
        napi_create_object(env, &ppObj);
        napi_set_named_property(env, ppObj, "protocol",
            CreateInt32Napi(env, static_cast<int32_t>(d->host.protocolPorts[i].protocol)));
        napi_set_named_property(env, ppObj, "port",
            CreateInt32Napi(env, d->host.protocolPorts[i].port));
        napi_set_element(env, protoPortsArr, i, ppObj);
    }
    napi_set_named_property(env, hostObj, "protocolPorts", protoPortsArr);

    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    napi_value argv[1] = { hostObj };
    napi_call_function(env, undefined, jsCb, 1, argv, nullptr);

    delete d;
}

static void CompleteCallJs(napi_env env, napi_value jsCb, void* context, void* data)
{
    if (env == nullptr || jsCb == nullptr || data == nullptr) {
        delete static_cast<CompleteData*>(data);
        return;
    }
    auto* d = static_cast<CompleteData*>(data);

    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    napi_value argv[1] = { CreateBoolNapi(env, d->cancelled) };
    napi_call_function(env, undefined, jsCb, 1, argv, nullptr);

    delete d;
}

static void TsfnRelease(napi_env env, void* rawCtx, void* rawHint)
{
    // Context cleanup is handled by the caller
}

// ---- scanStart ----

static napi_value ScanStart(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value args[4] = {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 4) {
        OH_LOG_ERROR(LOG_APP, "scanStart requires 4 arguments: config, onProgress, onHostFound, onComplete");
        napi_value undefined = nullptr;
        napi_get_undefined(env, &undefined);
        return undefined;
    }

    // Parse config
    netscan::ScanConfig config;
    napi_value subnetVal = nullptr;
    napi_value timeoutVal = nullptr;
    GetOptionalNamedProperty(env, args[0], "subnetBase", &subnetVal);
    GetOptionalNamedProperty(env, args[0], "hostTimeoutMs", &timeoutVal);
    config.subnetBase = GetStringFromNapi(env, subnetVal);
    napi_valuetype vt = napi_undefined;
    napi_typeof(env, timeoutVal, &vt);
    if (vt == napi_number) {
        config.hostTimeoutMs = GetInt32FromNapi(env, timeoutVal);
    }

    if (config.subnetBase.empty()) {
        OH_LOG_ERROR(LOG_APP, "scanStart: subnetBase is empty");
        napi_value undefined = nullptr;
        napi_get_undefined(env, &undefined);
        return undefined;
    }

    // Create threadsafe functions for the 3 callbacks
    napi_value asyncResource = nullptr;
    napi_create_object(env, &asyncResource);

    napi_threadsafe_function progressTsfn = nullptr;
    napi_threadsafe_function hostFoundTsfn = nullptr;
    napi_threadsafe_function completeTsfn = nullptr;

    napi_value progressName = nullptr;
    napi_create_string_utf8(env, "scanProgress", 12, &progressName);
    napi_create_threadsafe_function(env, args[1], asyncResource, progressName,
                                    0, 1, nullptr, TsfnRelease, nullptr, ProgressCallJs, &progressTsfn);

    napi_value hostFoundName = nullptr;
    napi_create_string_utf8(env, "scanHostFound", 13, &hostFoundName);
    napi_create_threadsafe_function(env, args[2], asyncResource, hostFoundName,
                                    0, 1, nullptr, TsfnRelease, nullptr, HostFoundCallJs, &hostFoundTsfn);

    napi_value completeName = nullptr;
    napi_create_string_utf8(env, "scanComplete", 12, &completeName);
    napi_create_threadsafe_function(env, args[3], asyncResource, completeName,
                                    0, 1, nullptr, TsfnRelease, nullptr, CompleteCallJs, &completeTsfn);

    OH_LOG_INFO(LOG_APP, "Starting network scan on subnet %{public}s.0/24, timeout=%dms",
                config.subnetBase.c_str(), config.hostTimeoutMs);

    auto* scanner = GetScanner();
    scanner->startScan(config,
        [progressTsfn](int scanned, int total, const std::string& currentIP) {
            auto* data = new ProgressData{scanned, total, currentIP};
            napi_call_threadsafe_function(progressTsfn, data, napi_tsfn_nonblocking);
        },
        [hostFoundTsfn](const netscan::DiscoveredHost& host) {
            // Log the found host with protocol ports
            std::string protoList;
            for (size_t i = 0; i < host.protocolPorts.size(); i++) {
                if (i > 0) protoList += ",";
                switch (host.protocolPorts[i].protocol) {
                    case netscan::Protocol::FTP: protoList += "FTP:"; break;
                    case netscan::Protocol::SFTP: protoList += "SFTP:"; break;
                    case netscan::Protocol::FTPS: protoList += "FTPS:"; break;
                    case netscan::Protocol::WEBDAV: protoList += "WebDAV:"; break;
                    case netscan::Protocol::WEBDAVS: protoList += "WebDAVS:"; break;
                    case netscan::Protocol::SMB: protoList += "SMB:"; break;
                }
                protoList += std::to_string(host.protocolPorts[i].port);
            }
            OH_LOG_INFO(LOG_APP, "Host found: %{public}s [%{public}s]",
                        host.ip.c_str(), protoList.c_str());

            auto* data = new HostFoundData{host};
            napi_call_threadsafe_function(hostFoundTsfn, data, napi_tsfn_nonblocking);
        },
        [progressTsfn, hostFoundTsfn, completeTsfn](bool cancelled) {
            OH_LOG_INFO(LOG_APP, "Scan completed, cancelled=%{public}s", cancelled ? "true" : "false");

            auto* data = new CompleteData{cancelled};
            napi_call_threadsafe_function(completeTsfn, data, napi_tsfn_nonblocking);

            // Release all threadsafe functions after scan completes
            napi_release_threadsafe_function(progressTsfn, napi_tsfn_release);
            napi_release_threadsafe_function(hostFoundTsfn, napi_tsfn_release);
            napi_release_threadsafe_function(completeTsfn, napi_tsfn_release);
        }
    );

    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

// ---- scanStop ----

static napi_value ScanStop(napi_env env, napi_callback_info info)
{
    auto* scanner = GetScanner();
    scanner->cancelScan();
    OH_LOG_INFO(LOG_APP, "Network scan cancelled");

    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

// ---- scanIsRunning ----

static napi_value ScanIsRunning(napi_env env, napi_callback_info info)
{
    auto* scanner = GetScanner();
    return CreateBoolNapi(env, scanner->isScanning());
}

// ---- smbEnumShares ----

static napi_value SmbEnumShares(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    netscan::SMBEnumConfig config;
    if (argc >= 1) {
        napi_value v = nullptr;
        GetOptionalNamedProperty(env, args[0], "host", &v);
        config.host = GetStringFromNapi(env, v);
        GetOptionalNamedProperty(env, args[0], "port", &v);
        napi_valuetype vt = napi_undefined;
        napi_typeof(env, v, &vt);
        if (vt == napi_number) config.port = GetInt32FromNapi(env, v);
        GetOptionalNamedProperty(env, args[0], "username", &v);
        config.username = GetStringFromNapi(env, v);
        GetOptionalNamedProperty(env, args[0], "password", &v);
        config.password = GetStringFromNapi(env, v);
        GetOptionalNamedProperty(env, args[0], "domain", &v);
        config.domain = GetStringFromNapi(env, v);
        GetOptionalNamedProperty(env, args[0], "timeoutMs", &v);
        vt = napi_undefined;
        napi_typeof(env, v, &vt);
        if (vt == napi_number) config.timeoutMs = GetInt32FromNapi(env, v);
    }

    if (config.host.empty()) {
        napi_value obj = nullptr;
        napi_create_object(env, &obj);
        napi_set_named_property(env, obj, "success", CreateBoolNapi(env, false));
        napi_set_named_property(env, obj, "message", CreateStringNapi(env, "host is empty"));
        napi_value emptyArr = nullptr;
        napi_create_array_with_length(env, 0, &emptyArr);
        napi_set_named_property(env, obj, "shares", emptyArr);
        return obj;
    }

    OH_LOG_INFO(LOG_APP, "Enumerating SMB shares on %{public}s:%d", config.host.c_str(), config.port);

    auto* scanner = GetScanner();
    auto result = scanner->enumerateSMBShares(config);

    napi_value obj = nullptr;
    napi_create_object(env, &obj);
    napi_set_named_property(env, obj, "success", CreateBoolNapi(env, result.success));
    napi_set_named_property(env, obj, "message", CreateStringNapi(env, result.message));

    napi_value sharesArr = nullptr;
    napi_create_array_with_length(env, result.shares.size(), &sharesArr);
    for (size_t i = 0; i < result.shares.size(); i++) {
        const auto& share = result.shares[i];
        napi_value shareObj = nullptr;
        napi_create_object(env, &shareObj);
        napi_set_named_property(env, shareObj, "name", CreateStringNapi(env, share.name));
        napi_set_named_property(env, shareObj, "remark", CreateStringNapi(env, share.remark));
        napi_set_named_property(env, shareObj, "type", CreateInt32Napi(env, static_cast<int32_t>(share.type)));
        napi_set_named_property(env, shareObj, "isHidden", CreateBoolNapi(env, share.isHidden));
        napi_set_named_property(env, shareObj, "isDiskShare", CreateBoolNapi(env, share.isDiskShare));
        napi_set_element(env, sharesArr, i, shareObj);
    }
    napi_set_named_property(env, obj, "shares", sharesArr);

    return obj;
}

// ---- Registration ----

void RegisterScannerFunctions(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "scanStart", nullptr, ScanStart, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "scanStop", nullptr, ScanStop, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "scanIsRunning", nullptr, ScanIsRunning, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "smbEnumShares", nullptr, SmbEnumShares, nullptr, nullptr, nullptr, napi_default, nullptr },
    };

    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    OH_LOG_INFO(LOG_APP, "Scanner native functions registered");
}
