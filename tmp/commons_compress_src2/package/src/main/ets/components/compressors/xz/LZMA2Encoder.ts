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
import type FilterEncoder from './FilterEncoder'
import LZMA2Options from './LZMA2Options'
import Exception from '../../util/Exception'
import LZMAEncoder from './lzma/LZMAEncoder'
import FinishableOutputStream from './FinishableOutputStream'
import ArrayCache from './ArrayCache'
import Long from "../../util/long/index"

export default class LZMA2Encoder extends LZMA2Coder implements FilterEncoder {
    private options: LZMA2Options;
    private props: Int8Array = new Int8Array(1);

    constructor(options: LZMA2Options) {
        super()
        if (options.getPresetDict() != null) {
            throw new Exception("XZ doesn't support a preset dictionary for now");
        } else {
            if (options.getMode() == LZMA2Options.MODE_UNCOMPRESSED) {
                this.props[0] = 0;
            } else {
                let d: number = Math.max(options.getDictSize(), LZMA2Options.MODE_UNCOMPRESSED);
                this.props[0] = (LZMAEncoder.getDistSlot(d - 1) - 23);
            }
            this.options = this.copyObject(options);
        }
    }

    public copyObject(orig) {
        var copy = Object.create(Object.getPrototypeOf(orig));
        this.copyOwnPropertiesFrom(copy, orig);
        return copy;
    }

    public copyOwnPropertiesFrom(target, source) {
        Object
            .getOwnPropertyNames(source)
            .forEach(function (propKey) {
                var desc = Object.getOwnPropertyDescriptor(source, propKey);
                Object.defineProperty(target, propKey, desc);
            });
        return target;
    }

    public getFilterID(): Long {
        return Long.fromNumber(33);
    }

    public getFilterProps(): Int8Array {
        return this.props;
    }

    public supportsFlushing(): boolean {
        return true;
    }

    public getOutputStream(out: FinishableOutputStream, arrayCache: ArrayCache): FinishableOutputStream {
        return this.options.getOutputStream(out, arrayCache);
    }
}
