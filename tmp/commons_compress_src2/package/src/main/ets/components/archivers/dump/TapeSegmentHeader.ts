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
import { SEGMENT_TYPE } from './Enumeration'

export default class TapeSegmentHeader {
    public typeField: SEGMENT_TYPE = null;
    public volume: int;
    public ino: int;
    public count: int;
    public holes: int;
    public cdata: Int8Array = new Int8Array(512);

    public getType(): SEGMENT_TYPE {
        let s: SEGMENT_TYPE = this.typeField
        return this.typeField;
    }

    public getVolume(): int {
        return this.volume;
    }

    public getIno(): int {
        return this.ino;
    }

    setIno(ino: int) {
        this.ino = ino;
    }

    public getCount(): int {
        return this.count;
    }

    public getHoles(): int {
        return this.holes;
    }

    public getCdata(idx: int): int {
        return this.cdata[idx];
    }
}