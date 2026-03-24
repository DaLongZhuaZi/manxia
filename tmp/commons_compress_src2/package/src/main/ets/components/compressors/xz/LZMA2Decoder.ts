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
import LZMA2Coder from './LZMA2Coder'
import Exception from '../../util/Exception'
import LZMA2InputStream from './LZMA2InputStream'
import InputStream from '../../util/InputStream'
import ArrayCache from './ArrayCache'

export default class LZMA2Decoder extends LZMA2Coder {
    private dictSize: number;

    constructor(props) {
        super()
        if (props.length == 1 && (props[0] & 255) <= 37) {
            this.dictSize = 2 | props[0] & 1;
            this.dictSize <<= (props[0] >>> 1) + 11;
        } else {
            throw new Exception("Unsupported LZMA2 properties");
        }
    }

    public getMemoryUsage(): number {
        return 104 + this.getDictSize(this.dictSize) / 1024;
    }

    private getDictSize(dictSize: number): number {
        if (dictSize >= 4096 && dictSize <= 2147483632) {
            return dictSize + 15 & -16;
        } else {
            throw new Exception("Unsupported dictionary size " + dictSize);
        }
    }

    public getInputStream(inputStream: InputStream, arrayCache: ArrayCache): InputStream {
        return new LZMA2InputStream(inputStream, this.dictSize, null, arrayCache);
    }
}