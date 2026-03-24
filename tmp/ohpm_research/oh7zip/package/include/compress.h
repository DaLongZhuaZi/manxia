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

#ifndef __7Z_COMPRESS_H__
#define __7Z_COMPRESS_H__

#include "common.h"
#include <future>
namespace Oh7zip {

class EXPORT_DEFAULT Compress {
public:
    Compress() = default;
    virtual ~Compress() {}
    ErrorInfo CompressSync(std::shared_ptr<Config7z> config);
    std::shared_future<ErrorInfo> CompressAsync(std::shared_ptr<Config7z> config);
};

} // namespace Oh7zip

#endif