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

export default class ArrayCache {
    private static dummyCache: ArrayCache = new ArrayCache();
    private static defaultCache: ArrayCache = ArrayCache.dummyCache;

    public static getDummyCache(): ArrayCache {
        return ArrayCache.dummyCache;
    }

    public static getDefaultCache(): ArrayCache {
        return ArrayCache.defaultCache;
    }

    public static setDefaultCache(arrayCache: ArrayCache) {
        if (arrayCache == null) {
            throw new Exception();
        } else {
            ArrayCache.defaultCache = arrayCache;
        }
    }

    constructor() {
    }

    public getByteArray(size: number, fillWithZeros: boolean): Int8Array {
        return new Int8Array(size);
    }

    public putArrayInt8Array(array: Int8Array) {
    }

    public getIntArray(size: number, fillWithZeros: boolean): Int32Array {
        return new Int32Array(size);
    }

    public putArray(array: Int32Array) {
    }
}

