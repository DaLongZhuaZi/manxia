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

import { CachedAvailability } from './CachedAvailability';

export default class BrotliUtils {
    private static cachedBrotliAvailability: CachedAvailability;

    constructor() {

    }

    public static isBrotliCompressionAvailable(): boolean {
        let cachedResult: CachedAvailability = BrotliUtils.cachedBrotliAvailability;
        if (cachedResult != CachedAvailability.DONT_CACHE) {
            return cachedResult == CachedAvailability.CACHED_AVAILABLE;
        }
        return BrotliUtils.internalIsBrotliCompressionAvailable();
    }

    private static internalIsBrotliCompressionAvailable(): boolean {
        try {
            return true;
        } catch (exception) {
            return false;
        }
    }

    public static setCacheBrotliAvailablity(doCache: boolean): void {
        if (!doCache) {
            BrotliUtils.cachedBrotliAvailability = CachedAvailability.DONT_CACHE;
        } else if (BrotliUtils.cachedBrotliAvailability == CachedAvailability.DONT_CACHE) {
            let hasBrotli: boolean = BrotliUtils.internalIsBrotliCompressionAvailable();
            BrotliUtils.cachedBrotliAvailability = hasBrotli ? CachedAvailability.CACHED_AVAILABLE
                                                             : CachedAvailability.CACHED_UNAVAILABLE;
        }
    }

    static getCachedBrotliAvailability(): CachedAvailability {
        return BrotliUtils.cachedBrotliAvailability;
    }
}
