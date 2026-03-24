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
import FinishableOutputStream from './FinishableOutputStream'
import ArrayCache from './ArrayCache'
import InputStream from '../../util/InputStream'
import type FilterEncoder from './FilterEncoder'

export default abstract class FilterOptions {
    public static getEncoderMemoryUsage(options: Array<FilterOptions>): number {
        let num: number = 0;

        for (let i: number = 0; i < options.length; ++i) {
            num += options[i].getEncoderMemoryUsage();
        }

        return num;
    }

    public static getDecoderMemoryUsage(options: Array<FilterOptions>): number {
        let num: number = 0;

        for (let i: number = 0; i < options.length; ++i) {
            num += options[i].getDecoderMemoryUsage();
        }

        return num;
    }

    public abstract getEncoderMemoryUsage(): number;

    public getOutputStreamFinishable(out: FinishableOutputStream): FinishableOutputStream {
        return this.getOutputStream(out, ArrayCache.getDefaultCache());
    }

    public abstract getOutputStream(out: FinishableOutputStream, arrayCache: ArrayCache): FinishableOutputStream;

    public abstract getDecoderMemoryUsage(): number;

    public getInputStream(inputStream: InputStream): InputStream {
        return this.getInputStreamArray(inputStream, ArrayCache.getDefaultCache());
    }

    public abstract getInputStreamArray(inputStream: InputStream, arrayCache: ArrayCache): InputStream;

    abstract getFilterEncoder(): FilterEncoder;

    constructor() {
    }
}
