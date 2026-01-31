/**
 * CURL全局初始化管理
 * 使用引用计数确保curl_global_init/cleanup只调用一次
 * 
 * 文件路径: entry/src/main/cpp/webdav/curl_global.h
 */

#ifndef CURL_GLOBAL_H
#define CURL_GLOBAL_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * 增加curl引用计数，首次调用时初始化curl全局状态
 * 必须在使用任何curl功能之前调用
 */
void curl_ref_init(void);

/**
 * 减少curl引用计数，最后一个引用释放时清理curl全局状态
 * 必须与curl_ref_init配对调用
 */
void curl_ref_cleanup(void);

#ifdef __cplusplus
}
#endif

#endif // CURL_GLOBAL_H
