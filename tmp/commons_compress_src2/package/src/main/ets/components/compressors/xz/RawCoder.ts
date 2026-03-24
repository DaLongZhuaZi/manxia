/*
 * Copyright (c) 2022 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import Exception from '../../util/Exception'

export default class RawCoder {
    constructor() {
    }

    static validate(filters): void {
        for (let i = 0; i < filters.length - 1; ++i) {
            if (!filters[i].nonLastOK()) {
                throw new Exception("Unsupported XZ filter chain");
            }
        }

        if (!filters[filters.length - 1].lastOK()) {
            throw new Exception("Unsupported XZ filter chain");
        }

        let changesSizeCount = 0;

        for (let i = 0; i < filters.length; ++i) {
            if (filters[i].changesSize()) {
                ++changesSizeCount;
            }
        }

        if (changesSizeCount > 3) {
            throw new Exception("Unsupported XZ filter chain");
        }
    }
}
