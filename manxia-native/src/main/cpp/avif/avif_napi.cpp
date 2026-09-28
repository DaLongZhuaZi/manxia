/**
 * AVIF解码器NAPI接口
 * 提供ArkTS调用Native AVIF解码功能的桥接
 * 支持异步解码以避免主线程阻塞
 */

#include <napi/native_api.h>
#include <hilog/log.h>
#include <multimedia/image_framework/image_pixel_map_napi.h>
#include <cstring>
#include <thread>
#include <vector>
#include "avif_decoder.h"

#undef LOG_TAG
#define LOG_TAG "AvifNapi"
#define LOG_DOMAIN 0x3201

#define NAPI_LOGI(...) OH_LOG_INFO(LOG_APP, __VA_ARGS__)
#define NAPI_LOGE(...) OH_LOG_ERROR(LOG_APP, __VA_ARGS__)

// 全局解码器实例
static avif::AvifDecoder g_decoder;

// 异步解码上下文
struct AsyncDecodeContext {
    napi_async_work work;
    napi_deferred deferred;
    napi_ref callbackRef;
    std::vector<uint8_t> inputData;
    avif::DecodedImage result;
    bool hasCallback;
};

/**
 * 检查是否为AVIF格式
 * JS: isAvifFormat(data: ArrayBuffer): boolean
 */
static napi_value IsAvifFormat(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        napi_value result;
        napi_get_boolean(env, false, &result);
        return result;
    }
    
    // 获取ArrayBuffer数据
    void* data = nullptr;
    size_t dataSize = 0;
    bool isArrayBuffer = false;
    napi_is_arraybuffer(env, args[0], &isArrayBuffer);
    
    if (isArrayBuffer) {
        napi_get_arraybuffer_info(env, args[0], &data, &dataSize);
    } else {
        // 尝试作为TypedArray处理
        napi_typedarray_type type;
        size_t length;
        void* arrayData;
        napi_value arrayBuffer;
        size_t offset;
        napi_status status = napi_get_typedarray_info(env, args[0], &type, &length, &arrayData, &arrayBuffer, &offset);
        if (status == napi_ok) {
            data = arrayData;
            dataSize = length;
        }
    }
    
    bool isAvif = false;
    if (data && dataSize > 0) {
        isAvif = avif::AvifDecoder::IsAvifFormat(static_cast<const uint8_t*>(data), dataSize);
    }
    
    napi_value result;
    napi_get_boolean(env, isAvif, &result);
    return result;
}

/**
 * 检查libavif是否可用
 * JS: isLibavifAvailable(): boolean
 */
static napi_value IsLibavifAvailable(napi_env env, napi_callback_info info) {
    bool available = avif::AvifDecoder::IsLibavifAvailable();
    napi_value result;
    napi_get_boolean(env, available, &result);
    return result;
}

/**
 * 解码AVIF图片为RGBA数据
 * JS: decodeAvifToRgba(data: ArrayBuffer): { width: number, height: number, pixels: Uint8Array } | null
 */
static napi_value DecodeAvifToRgba(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        NAPI_LOGE("decodeAvifToRgba: missing argument");
        napi_value null_result;
        napi_get_null(env, &null_result);
        return null_result;
    }
    
    // 获取输入数据
    void* data = nullptr;
    size_t dataSize = 0;
    bool isArrayBuffer = false;
    napi_is_arraybuffer(env, args[0], &isArrayBuffer);
    
    if (isArrayBuffer) {
        napi_get_arraybuffer_info(env, args[0], &data, &dataSize);
    } else {
        napi_typedarray_type type;
        size_t length;
        void* arrayData;
        napi_value arrayBuffer;
        size_t offset;
        napi_status status = napi_get_typedarray_info(env, args[0], &type, &length, &arrayData, &arrayBuffer, &offset);
        if (status == napi_ok) {
            data = arrayData;
            dataSize = length;
        }
    }
    
    if (!data || dataSize == 0) {
        NAPI_LOGE("decodeAvifToRgba: invalid input data");
        napi_value null_result;
        napi_get_null(env, &null_result);
        return null_result;
    }
    
    NAPI_LOGI("decodeAvifToRgba: decoding %zu bytes", dataSize);
    
    // 解码AVIF
    avif::DecodedImage decoded = g_decoder.Decode(static_cast<const uint8_t*>(data), dataSize);
    
    if (!decoded.success) {
        NAPI_LOGE("decodeAvifToRgba: decode failed - %s", decoded.error.c_str());
        napi_value null_result;
        napi_get_null(env, &null_result);
        return null_result;
    }
    
    NAPI_LOGI("decodeAvifToRgba: decoded %ux%u image", decoded.width, decoded.height);
    
    // 创建返回对象
    napi_value result;
    napi_create_object(env, &result);
    
    // 设置width
    napi_value widthValue;
    napi_create_uint32(env, decoded.width, &widthValue);
    napi_set_named_property(env, result, "width", widthValue);
    
    // 设置height
    napi_value heightValue;
    napi_create_uint32(env, decoded.height, &heightValue);
    napi_set_named_property(env, result, "height", heightValue);
    
    // 创建pixels Uint8Array
    napi_value pixelsArrayBuffer;
    void* pixelsData;
    napi_create_arraybuffer(env, decoded.pixels.size(), &pixelsData, &pixelsArrayBuffer);
    memcpy(pixelsData, decoded.pixels.data(), decoded.pixels.size());
    
    napi_value pixelsTypedArray;
    napi_create_typedarray(env, napi_uint8_array, decoded.pixels.size(), pixelsArrayBuffer, 0, &pixelsTypedArray);
    napi_set_named_property(env, result, "pixels", pixelsTypedArray);
    
    return result;
}

/**
 * 获取AVIF图片信息
 * JS: getAvifInfo(data: ArrayBuffer): { width: number, height: number } | null
 */
static napi_value GetAvifInfo(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        napi_value null_result;
        napi_get_null(env, &null_result);
        return null_result;
    }
    
    void* data = nullptr;
    size_t dataSize = 0;
    bool isArrayBuffer = false;
    napi_is_arraybuffer(env, args[0], &isArrayBuffer);
    
    if (isArrayBuffer) {
        napi_get_arraybuffer_info(env, args[0], &data, &dataSize);
    } else {
        napi_typedarray_type type;
        size_t length;
        void* arrayData;
        napi_value arrayBuffer;
        size_t offset;
        napi_status status = napi_get_typedarray_info(env, args[0], &type, &length, &arrayData, &arrayBuffer, &offset);
        if (status == napi_ok) {
            data = arrayData;
            dataSize = length;
        }
    }
    
    if (!data || dataSize == 0) {
        napi_value null_result;
        napi_get_null(env, &null_result);
        return null_result;
    }
    
    uint32_t width = 0, height = 0;
    bool success = g_decoder.GetImageInfo(static_cast<const uint8_t*>(data), dataSize, width, height);
    
    if (!success) {
        napi_value null_result;
        napi_get_null(env, &null_result);
        return null_result;
    }
    
    napi_value result;
    napi_create_object(env, &result);
    
    napi_value widthValue, heightValue;
    napi_create_uint32(env, width, &widthValue);
    napi_create_uint32(env, height, &heightValue);
    napi_set_named_property(env, result, "width", widthValue);
    napi_set_named_property(env, result, "height", heightValue);
    
    return result;
}

// ==================== 异步解码实现 ====================

/**
 * 异步解码执行函数（在工作线程中执行）
 */
static void AsyncDecodeExecute(napi_env env, void* data) {
    AsyncDecodeContext* context = static_cast<AsyncDecodeContext*>(data);
    NAPI_LOGI("AsyncDecodeExecute: decoding %zu bytes in worker thread", context->inputData.size());
    
    // 在工作线程中执行解码
    context->result = g_decoder.Decode(context->inputData.data(), context->inputData.size());
    
    if (context->result.success) {
        NAPI_LOGI("AsyncDecodeExecute: decode success %ux%u", context->result.width, context->result.height);
    } else {
        NAPI_LOGE("AsyncDecodeExecute: decode failed - %s", context->result.error.c_str());
    }
}

/**
 * 异步解码完成回调（在主线程中执行）
 */
static void AsyncDecodeComplete(napi_env env, napi_status status, void* data) {
    AsyncDecodeContext* context = static_cast<AsyncDecodeContext*>(data);
    
    napi_value result;
    
    if (status != napi_ok || !context->result.success) {
        // 解码失败，返回null
        napi_get_null(env, &result);
    } else {
        // 创建返回对象
        napi_create_object(env, &result);
        
        // 设置width
        napi_value widthValue;
        napi_create_uint32(env, context->result.width, &widthValue);
        napi_set_named_property(env, result, "width", widthValue);
        
        // 设置height
        napi_value heightValue;
        napi_create_uint32(env, context->result.height, &heightValue);
        napi_set_named_property(env, result, "height", heightValue);
        
        // 创建pixels Uint8Array
        napi_value pixelsArrayBuffer;
        void* pixelsData;
        napi_create_arraybuffer(env, context->result.pixels.size(), &pixelsData, &pixelsArrayBuffer);
        memcpy(pixelsData, context->result.pixels.data(), context->result.pixels.size());
        
        napi_value pixelsTypedArray;
        napi_create_typedarray(env, napi_uint8_array, context->result.pixels.size(), pixelsArrayBuffer, 0, &pixelsTypedArray);
        napi_set_named_property(env, result, "pixels", pixelsTypedArray);
    }
    
    // 解析Promise
    if (context->deferred) {
        if (status == napi_ok && context->result.success) {
            napi_resolve_deferred(env, context->deferred, result);
        } else {
            napi_reject_deferred(env, context->deferred, result);
        }
    }
    
    // 清理资源
    napi_delete_async_work(env, context->work);
    delete context;
}

/**
 * 异步解码AVIF图片（返回Promise）
 * JS: decodeAvifAsync(data: ArrayBuffer): Promise<{ width: number, height: number, pixels: Uint8Array } | null>
 */
static napi_value DecodeAvifAsync(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        napi_value undefined;
        napi_get_undefined(env, &undefined);
        return undefined;
    }
    
    // 获取输入数据
    void* data = nullptr;
    size_t dataSize = 0;
    bool isArrayBuffer = false;
    napi_is_arraybuffer(env, args[0], &isArrayBuffer);
    
    if (isArrayBuffer) {
        napi_get_arraybuffer_info(env, args[0], &data, &dataSize);
    } else {
        napi_typedarray_type type;
        size_t length;
        void* arrayData;
        napi_value arrayBuffer;
        size_t offset;
        napi_status status = napi_get_typedarray_info(env, args[0], &type, &length, &arrayData, &arrayBuffer, &offset);
        if (status == napi_ok) {
            data = arrayData;
            dataSize = length;
        }
    }
    
    if (!data || dataSize == 0) {
        NAPI_LOGE("DecodeAvifAsync: invalid input data");
        napi_value undefined;
        napi_get_undefined(env, &undefined);
        return undefined;
    }
    
    // 创建异步上下文
    AsyncDecodeContext* context = new AsyncDecodeContext();
    context->inputData.resize(dataSize);
    memcpy(context->inputData.data(), data, dataSize);
    context->hasCallback = false;
    
    // 创建Promise
    napi_value promise;
    napi_create_promise(env, &context->deferred, &promise);
    
    // 创建异步工作
    napi_value resourceName;
    napi_create_string_utf8(env, "AvifDecodeAsync", NAPI_AUTO_LENGTH, &resourceName);
    
    napi_status status = napi_create_async_work(
        env,
        nullptr,
        resourceName,
        AsyncDecodeExecute,
        AsyncDecodeComplete,
        context,
        &context->work
    );
    
    if (status != napi_ok) {
        NAPI_LOGE("DecodeAvifAsync: failed to create async work");
        delete context;
        napi_value undefined;
        napi_get_undefined(env, &undefined);
        return undefined;
    }
    
    // 将工作加入队列
    status = napi_queue_async_work(env, context->work);
    if (status != napi_ok) {
        NAPI_LOGE("DecodeAvifAsync: failed to queue async work");
        napi_delete_async_work(env, context->work);
        delete context;
        napi_value undefined;
        napi_get_undefined(env, &undefined);
        return undefined;
    }
    
    NAPI_LOGI("DecodeAvifAsync: async work queued for %zu bytes", dataSize);
    return promise;
}

/**
 * 模块初始化
 */
EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    NAPI_LOGI("AvifDecoder module initializing...");
    
    napi_property_descriptor desc[] = {
        {"isAvifFormat", nullptr, IsAvifFormat, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isLibavifAvailable", nullptr, IsLibavifAvailable, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"decodeAvifToRgba", nullptr, DecodeAvifToRgba, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"decodeAvifAsync", nullptr, DecodeAvifAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getAvifInfo", nullptr, GetAvifInfo, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    
    NAPI_LOGI("AvifDecoder module initialized, libavif available: %d", avif::AvifDecoder::IsLibavifAvailable());
    
    return exports;
}
EXTERN_C_END

// 模块描述
static napi_module avifModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "avif_decoder",
    .nm_priv = nullptr,
    .reserved = {0},
};

// 模块注册
extern "C" __attribute__((constructor)) void RegisterAvifModule(void) {
    napi_module_register(&avifModule);
}
