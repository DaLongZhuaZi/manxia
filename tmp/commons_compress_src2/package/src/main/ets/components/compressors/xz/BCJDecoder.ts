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
import BCJCoder from './BCJCoder'
import type FilterDecoder from './FilterDecoder'
import Exception from '../../util/Exception'
import InputStream from '../../util/InputStream'
import X86 from './simple/x86'
import PowerPC from './simple/PowerPC'
import IA64 from './simple/IA64'
import ARM from './simple/ARM'
import ARMThumb from './simple/ARMThumb'
import SPARC from './simple/SPARC'
import ArrayCache from './ArrayCache'
import SimpleInputStream from './SimpleInputStream'
import Long from "../../util/long/index"

export default class BCJDecoder extends BCJCoder implements FilterDecoder {
    private filterID: Long;
    private startOffset: number;

    constructor(filterID: Long, props: Int8Array) {
        super()
        BCJCoder.isBCJFilterID(filterID);

        this.filterID = filterID;
        if (props.length == 0) {
            this.startOffset = 0;
        } else {
            if (props.length != 4) {
                throw new Exception("Unsupported BCJ filter properties");
            }

            let n = 0;

            for (let i = 0; i < 4; ++i) {
                n |= (props[i] & 255) << i * 8;
            }

            this.startOffset = n;
        }

    }

    public getMemoryUsage(): number {
        return 5;
    }

    public getInputStream(inputStream: InputStream, arrayCache: ArrayCache): InputStream {
        let simpleFilter = null;
        if (this.filterID == Long.fromNumber(4)) {
            simpleFilter = new X86(false, this.startOffset);
        } else if (this.filterID == Long.fromNumber(5)) {
            simpleFilter = new PowerPC(false, this.startOffset);
        } else if (this.filterID == Long.fromNumber(6)) {
            simpleFilter = new IA64(false, this.startOffset);
        } else if (this.filterID == Long.fromNumber(7)) {
            simpleFilter = new ARM(false, this.startOffset);
        } else if (this.filterID == Long.fromNumber(8)) {
            simpleFilter = new ARMThumb(false, this.startOffset);
        } else if (this.filterID == Long.fromNumber(9)) {
            simpleFilter = new SPARC(false, this.startOffset);
        } else {
            false;
        }

        return new SimpleInputStream(inputStream, simpleFilter);
    }
}
