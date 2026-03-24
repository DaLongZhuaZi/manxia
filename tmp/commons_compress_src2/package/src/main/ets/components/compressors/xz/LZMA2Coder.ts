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
import type FilterCoder from './FilterCoder'

export default class LZMA2Coder implements FilterCoder {
    public static FILTER_ID: number = 33;

    constructor() {
    }

    public changesSize(): boolean {
        return true;
    }

    public nonLastOK(): boolean {
        return false;
    }

    public lastOK(): boolean {
        return true;
    }
}
