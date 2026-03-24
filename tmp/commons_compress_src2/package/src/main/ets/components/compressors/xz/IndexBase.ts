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
import Util from './Util'
import Long from "../../util/long/index"

export default class IndexBase {
    invalidIndexException: Exception;
    blocksSum: Long = Long.fromNumber(0);
    uncompressedSum: Long = Long.fromNumber(0);
    indexListSize: Long = Long.fromNumber(0);
    recordCount: Long = Long.fromNumber(0);

    constructor(invalidIndexException) {
        this.invalidIndexException = invalidIndexException;
    }

    private getUnpaddedIndexSize(): Long {
        return this.indexListSize.add(1 + Util.getVLISize(this.recordCount) + 4)
    }

    public getIndexSize(): Long {
        return this.getUnpaddedIndexSize().add(3).and(-4);
    }

    public getStreamSize(): Long {
        return Long.fromNumber(12)
            .add(this.blocksSum)
            .add(this.getIndexSize())
            .add(Long.fromNumber(12));
    }

    getIndexPaddingSize(): number {
        return (Long.fromNumber(4).sub(this.getUnpaddedIndexSize())
            .and(3)).toInt();
    }

    add(unpaddedSize: Long, uncompressedSize: Long): void {
        this.blocksSum = this.blocksSum.add(unpaddedSize.add(Long.fromNumber(3)).and(Long.fromNumber(-4)));
        this.uncompressedSum = this.uncompressedSum.add(uncompressedSize);
        this.indexListSize = this.indexListSize.add(Util.getVLISize(unpaddedSize) + Util.getVLISize(uncompressedSize));
        this.recordCount = this.recordCount.add(1);
        if (this.blocksSum.lessThan(Long.fromNumber(0)) || this.uncompressedSum.lessThan(Long.fromNumber(0)) ||
        this.getIndexSize().gt(Util.BACKWARD_SIZE_MAX) || this.getStreamSize().lessThan(Long.fromNumber(0))) {
            throw this.invalidIndexException;
        }
    }
}
