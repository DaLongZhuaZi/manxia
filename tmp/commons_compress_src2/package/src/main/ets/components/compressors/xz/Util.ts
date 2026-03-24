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
import Long from "../../util/long/index"

export default class Util {
    public static STREAM_HEADER_SIZE: number = 12;
    public static BACKWARD_SIZE_MAX: Long = Long.fromNumber(17179869184) ;
    public static BLOCK_HEADER_SIZE_MAX: number = 1024;
    public static VLI_MAX: Long = Long.fromString('9223372036854775807') ;
    public static VLI_SIZE_MAX: number = 9;

    constructor() {
    }

    public static getVLISize(num: Long): number {
        let size: number = 0;

        do {
            ++size;
            num = num.shiftRight(7);
        } while (!num.eq(0));

        return size;
    }
}