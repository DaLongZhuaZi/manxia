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
import Exception from '../../../util/Exception'

export default abstract class DeltaCoder {
    static DISTANCE_MIN: number = 1;
    static DISTANCE_MAX: number = 256;
    static DISTANCE_MASK: number = 255;
    distance: number;
    history: Int8Array = new Int8Array(256);
    pos: number = 0;

    constructor(distance: number) {
        if (distance >= 1 && distance <= 256) {
            this.distance = distance;
        } else {
            throw new Exception('DeltaCoder');
        }
    }
}
