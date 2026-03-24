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
import UnsupportedOperationException from "../../util/UnsupportedOperationException"
import CpioConstants from "./CpioConstants"
import System from "../../util/System";
import Long from "../../util/long/index";

export default class CpioUtil {
    static fileType(mode: Long): Long {
        return mode.and(CpioConstants.S_IFMT);
    }

    static byteArray2long(number: Int8Array, swapHalfWord: boolean): Long {
        if (number.length % 2 != 0) {
            throw new UnsupportedOperationException();
        }

        let ret: Long;
        let pos: number = 0;
        let tmp_number: Int8Array = new Int8Array(number.length);
        System.arraycopy(number, 0, tmp_number, 0, number.length);

        if (!swapHalfWord) {
            let tmp: number = 0;
            for (pos = 0; pos < tmp_number.length; pos++) {
                tmp = tmp_number[pos];
                tmp_number[pos++] = tmp_number[pos];
                tmp_number[pos] = tmp;
            }
        }

        ret = Long.fromNumber(tmp_number[0] & 0xFF);
        for (pos = 1; pos < tmp_number.length; pos++) {
            ret = ret.shl(8);
            ret = ret.or(tmp_number[pos] & 0xFF);
        }
        return ret;
    }

    static long2byteArray(number: Long, length: number,
                          swapHalfWord: boolean): Int8Array {
        let ret: Int8Array = new Int8Array(length);
        let pos: number = 0;
        let tmp_number: Long;

        if (length % 2 != 0 || length < 2) {
            throw new UnsupportedOperationException();
        }

        tmp_number = number;
        for (pos = length - 1; pos >= 0; pos--) {
            ret[pos] = (tmp_number.and(0xFF)).toNumber();
            tmp_number = tmp_number.shr(8);
        }

        if (!swapHalfWord) {
            let tmp: number = 0;
            for (pos = 0; pos < length; pos++) {
                tmp = ret[pos];
                ret[pos++] = ret[pos];
                ret[pos] = tmp;
            }
        }

        return ret;
    }
}
