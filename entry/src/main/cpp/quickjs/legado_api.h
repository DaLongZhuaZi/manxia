/**
 * Legado API Header - QuickJS兼容层
 * 
 * 定义Legado书源JS执行所需的API接口
 * 这些API模拟Rhino引擎中的Java互操作功能
 */

#ifndef LEGADO_API_H
#define LEGADO_API_H

#ifdef __cplusplus
extern "C" {
#endif

// QuickJS头文件
#include "quickjs/quickjs.h"

/**
 * 初始化Legado API
 * 将所有Legado兼容的API注入到JS全局对象中
 * 
 * @param ctx QuickJS上下文
 * @return 0成功，非0失败
 */
int legado_api_init(JSContext *ctx);

/**
 * 清理Legado API资源
 * 
 * @param ctx QuickJS上下文
 */
void legado_api_cleanup(JSContext *ctx);

/**
 * 设置书源信息
 * 用于source对象的属性
 * 
 * @param ctx QuickJS上下文
 * @param source_url 书源URL
 * @param source_name 书源名称
 * @param js_lib 书源的jsLib代码
 */
void legado_set_source_info(JSContext *ctx, 
                            const char *source_url,
                            const char *source_name,
                            const char *js_lib);

/**
 * 设置执行上下文
 * 设置key、page、result等变量
 * 
 * @param ctx QuickJS上下文
 * @param key 搜索关键字
 * @param page 页码
 * @param result 上一步结果
 * @param base_url 基础URL
 */
void legado_set_context(JSContext *ctx,
                        const char *key,
                        int page,
                        const char *result,
                        const char *base_url);

/**
 * 执行JS代码
 * 
 * @param ctx QuickJS上下文
 * @param code JS代码
 * @param code_len 代码长度
 * @param result_buf 结果缓冲区
 * @param result_buf_size 缓冲区大小
 * @return 0成功，非0失败
 */
int legado_eval(JSContext *ctx,
                const char *code,
                size_t code_len,
                char *result_buf,
                size_t result_buf_size);

// ============ Legado API 函数声明 ============

// java对象方法
// JSValue js_java_ajax(JSContext *ctx, JSValue this_val, int argc, JSValue *argv);
// JSValue js_java_post(JSContext *ctx, JSValue this_val, int argc, JSValue *argv);
// JSValue js_java_get(JSContext *ctx, JSValue this_val, int argc, JSValue *argv);
// JSValue js_java_put(JSContext *ctx, JSValue this_val, int argc, JSValue *argv);
// JSValue js_java_toast(JSContext *ctx, JSValue this_val, int argc, JSValue *argv);
// JSValue js_java_log(JSContext *ctx, JSValue this_val, int argc, JSValue *argv);
// JSValue js_java_base64_encode(JSContext *ctx, JSValue this_val, int argc, JSValue *argv);
// JSValue js_java_base64_decode(JSContext *ctx, JSValue this_val, int argc, JSValue *argv);
// JSValue js_java_hex_decode(JSContext *ctx, JSValue this_val, int argc, JSValue *argv);
// JSValue js_java_md5_encode(JSContext *ctx, JSValue this_val, int argc, JSValue *argv);
// JSValue js_java_time_format(JSContext *ctx, JSValue this_val, int argc, JSValue *argv);

// source对象方法
// JSValue js_source_get_variable(JSContext *ctx, JSValue this_val, int argc, JSValue *argv);
// JSValue js_source_set_variable(JSContext *ctx, JSValue this_val, int argc, JSValue *argv);
// JSValue js_source_get_login_info(JSContext *ctx, JSValue this_val, int argc, JSValue *argv);

// cookie对象方法
// JSValue js_cookie_get(JSContext *ctx, JSValue this_val, int argc, JSValue *argv);
// JSValue js_cookie_set(JSContext *ctx, JSValue this_val, int argc, JSValue *argv);
// JSValue js_cookie_remove(JSContext *ctx, JSValue this_val, int argc, JSValue *argv);

// book对象方法
// JSValue js_book_get_variable(JSContext *ctx, JSValue this_val, int argc, JSValue *argv);
// JSValue js_book_put_variable(JSContext *ctx, JSValue this_val, int argc, JSValue *argv);

// ============ NAPI辅助函数声明 ============

/**
 * 获取书源变量
 */
const char* legado_source_get_variable(const char *source_url);

/**
 * 设置书源变量
 */
void legado_source_set_variable(const char *source_url, const char *value);

/**
 * 获取Cookie
 */
const char* legado_cookie_get(const char *url);

/**
 * 设置Cookie
 */
void legado_cookie_set(const char *url, const char *cookie);

/**
 * 删除Cookie
 */
void legado_cookie_remove(const char *url);

/**
 * Base64编码
 */
const char* legado_base64_encode(const char *input);

/**
 * Base64解码
 */
const char* legado_base64_decode(const char *input);

/**
 * 十六进制解码
 */
const char* legado_hex_decode(const char *input);

/**
 * MD5编码
 */
const char* legado_md5_encode(const char *input);

#ifdef __cplusplus
}
#endif

#endif // LEGADO_API_H
