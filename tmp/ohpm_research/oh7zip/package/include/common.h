/*
 * Copyright (C) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the 'License');
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an 'AS IS' BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#ifndef __7Z_COMMON_H__
#define __7Z_COMMON_H__

#include <string>

#define EXPORT_DEFAULT __attribute__((visibility("default")))

struct Config7z {
    std::vector<std::string> src;
    std::string dst{""};
    std::string pwd{""};
    std::string fmt{"7z"};
    std::vector<std::string> xr;
};

enum class ErrorInfo {
    OK = 0,
    CONFIG_NULL,
    ILLEGAL_SRC,
    ILLEGAL_DST,
    DST_NO_PERMISSION,
    COMPRESS_FAIL,
    UNCOMPRESS_FAIL,
    ASYNCDATA_NULL,
    COMPRESS_FMT_NOT_SUPPURT,
    COMPRESS_FMT_SRC_ILLEGAL,
    MISSING_PASSWORD
};


#endif