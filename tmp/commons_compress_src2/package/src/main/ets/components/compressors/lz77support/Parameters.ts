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
import { int } from '../../util/CustomTypings'
import IllegalArgumentException from '../../util/IllegalArgumentException'

export default class Parameters {
    public static TRUE_MIN_BACK_REFERENCE_LENGTH: int = 3;

    public static builder(windowSize: int): Builder1 {
        return new Builder1(windowSize);
    }

    private windowSize: int;
    private minBackReferenceLength: int;
    private maxBackReferenceLength: int;
    private maxOffset: int;
    private maxLiteralLength: int;
    private niceBackReferenceLength: int;
    private maxCandidates: int;
    private lazyThreshold: int;
    private lazyMatching: boolean;

    constructor(windowSize: int, minBackReferenceLength: int, maxBackReferenceLength: int, maxOffset: int,
                maxLiteralLength: int, niceBackReferenceLength: int, maxCandidates: int, lazyMatching: boolean,
                lazyThreshold: int) {
        this.windowSize = Math.trunc(windowSize);
        this.minBackReferenceLength = Math.trunc(minBackReferenceLength);
        this.maxBackReferenceLength = Math.trunc(maxBackReferenceLength);
        this.maxOffset = Math.trunc(maxOffset);
        this.maxLiteralLength = Math.trunc(maxLiteralLength);
        this.niceBackReferenceLength = Math.trunc(niceBackReferenceLength);
        this.maxCandidates = Math.trunc(maxCandidates);
        this.lazyMatching = lazyMatching;
        this.lazyThreshold = Math.trunc(lazyThreshold);
    }

    public getWindowSize(): int {
        return this.windowSize;
    }

    public getMinBackReferenceLength(): int {
        return this.minBackReferenceLength;
    }

    public getMaxBackReferenceLength(): int {
        return this.maxBackReferenceLength;
    }

    public getMaxOffset(): int {
        return this.maxOffset;
    }

    public getMaxLiteralLength(): int {
        return this.maxLiteralLength;
    }

    public getNiceBackReferenceLength(): int {
        return this.niceBackReferenceLength;
    }

    public getMaxCandidates(): int {
        return this.maxCandidates;
    }

    public getLazyMatching(): boolean {
        return this.lazyMatching;
    }

    public getLazyMatchingThreshold(): int {
        return this.lazyThreshold;
    }

    public static isPowerOfTwo(x: int): boolean {
        return (x & (x - 1)) == 0;
    }
}

class Builder1 {
    private windowSize: int;
    private minBackReferenceLength: int;
    private maxBackReferenceLength: int;
    private maxOffset: int;
    private maxLiteralLength: int;
    private niceBackReferenceLength: int;
    private maxCandidates: int;
    private lazyThreshold: int;
    private lazyMatches: boolean;

    constructor(windowSize: int) {
        if (windowSize < 2 || !Parameters.isPowerOfTwo(windowSize)) {
            throw new IllegalArgumentException();
        }
        this.windowSize = Math.trunc(windowSize);
        this.minBackReferenceLength = Math.trunc(Parameters.TRUE_MIN_BACK_REFERENCE_LENGTH);
        this.maxBackReferenceLength = Math.trunc(windowSize - 1);
        this.maxOffset = Math.trunc(windowSize - 1);
        this.maxLiteralLength = Math.trunc(windowSize);
    }

    public withMinBackReferenceLength(minBackReferenceLength: int): Builder1 {
        this.minBackReferenceLength = Math.max(Parameters.TRUE_MIN_BACK_REFERENCE_LENGTH, minBackReferenceLength);
        if (this.windowSize < this.minBackReferenceLength) {
            throw new IllegalArgumentException();
        }
        if (this.maxBackReferenceLength < this.minBackReferenceLength) {
            this.maxBackReferenceLength = this.minBackReferenceLength;
        }
        return this;
    }

    public withMaxBackReferenceLength(maxBackReferenceLength: int): Builder1 {
        this.maxBackReferenceLength = maxBackReferenceLength < this.minBackReferenceLength ? this.minBackReferenceLength
                                                                                           : Math.min(maxBackReferenceLength, this.windowSize - 1);
        return this;
    }

    public withMaxOffset(maxOffset: int): Builder1 {
        this.maxOffset = maxOffset < 1 ? this.windowSize - 1 : Math.min(maxOffset, this.windowSize - 1);
        return this;
    }

    public withMaxLiteralLength(maxLiteralLength: int): Builder1 {
        this.maxLiteralLength = maxLiteralLength < 1 ? this.windowSize
                                                     : Math.min(maxLiteralLength, this.windowSize);
        return this;
    }

    public withNiceBackReferenceLength(niceLen: int): Builder1 {
        this.niceBackReferenceLength = niceLen;
        return this;
    }

    public withMaxNumberOfCandidates(maxCandidates: int): Builder1 {
        this.maxCandidates = maxCandidates;
        return this;
    }

    public withLazyMatching(lazy: boolean): Builder1 {
        this.lazyMatches = lazy;
        return this;
    }

    public withLazyThreshold(threshold: int): Builder1 {
        this.lazyThreshold = threshold;
        return this;
    }

    public tunedForSpeed(): Builder1 {
        this.niceBackReferenceLength = Math.max(this.minBackReferenceLength, Math.trunc(this.maxBackReferenceLength / 8));
        this.maxCandidates = Math.max(32, Math.trunc(this.windowSize / 1024));
        this.lazyMatches = false;
        this.lazyThreshold = this.minBackReferenceLength;
        return this;
    }

    public tunedForCompressionRatio(): Builder1 {
        this.niceBackReferenceLength = this.lazyThreshold = this.maxBackReferenceLength;
        this.maxCandidates = Math.max(32, Math.trunc(this.windowSize / 16));
        this.lazyMatches = true;
        return this;
    }

    public build(): Parameters {
        let niceLen: int = this.niceBackReferenceLength != null ? Math.trunc(this.niceBackReferenceLength)
                                                                : Math.max(this.minBackReferenceLength, Math.trunc(this.maxBackReferenceLength / 2));
        let candidates: int = this.maxCandidates != null ? this.maxCandidates : Math.max(256, Math.trunc(this.windowSize / 128));
        let lazy: boolean = this.lazyMatches == null || this.lazyMatches;
        let threshold: int = lazy ? (this.lazyThreshold != null ? this.lazyThreshold : niceLen) : this.minBackReferenceLength;

        return new Parameters(this.windowSize, this.minBackReferenceLength, this.maxBackReferenceLength,
            this.maxOffset, this.maxLiteralLength, niceLen, candidates, lazy, threshold);
    }
}


