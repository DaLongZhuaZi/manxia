/**
 * CURL全局初始化管理实现
 * 使用引用计数确保curl_global_init/cleanup只调用一次
 * 
 * 文件路径: entry/src/main/cpp/webdav/curl_global.cpp
 */

#include "curl_global.h"
#include <curl/curl.h>
#include <mutex>
#include <atomic>
#include <hilog/log.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3201
#define LOG_TAG "CurlGlobal"

// 静态变量用于引用计数管理
static std::mutex g_curlMutex;
static std::atomic<int> g_curlRefCount{0};
static std::atomic<bool> g_curlInitialized{false};

void curl_ref_init(void) {
    std::lock_guard<std::mutex> lock(g_curlMutex);
    int prevCount = g_curlRefCount.fetch_add(1);
    
    if (prevCount == 0 && !g_curlInitialized.load()) {
        CURLcode res = curl_global_init(CURL_GLOBAL_ALL);
        if (res != CURLE_OK) {
            OH_LOG_ERROR(LOG_APP, "curl_global_init failed with code: %{public}d", (int)res);
            g_curlRefCount.fetch_sub(1);
        } else {
            g_curlInitialized.store(true);
            OH_LOG_INFO(LOG_APP, "curl_global_init success, refCount=1");
        }
    } else {
        OH_LOG_DEBUG(LOG_APP, "curl_ref_init: refCount=%{public}d", prevCount + 1);
    }
}

void curl_ref_cleanup(void) {
    std::lock_guard<std::mutex> lock(g_curlMutex);
    int prevCount = g_curlRefCount.fetch_sub(1);
    
    if (prevCount <= 0) {
        // 异常情况：cleanup被多调用了
        OH_LOG_WARN(LOG_APP, "curl_ref_cleanup called but refCount was %{public}d", prevCount);
        g_curlRefCount.store(0); // 防止负数
        return;
    }
    
    if (prevCount == 1 && g_curlInitialized.load()) {
        // 最后一个引用，执行清理
        curl_global_cleanup();
        g_curlInitialized.store(false);
        OH_LOG_INFO(LOG_APP, "curl_global_cleanup done");
    } else {
        OH_LOG_DEBUG(LOG_APP, "curl_ref_cleanup: refCount=%{public}d", prevCount - 1);
    }
}
