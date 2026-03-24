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
import type FilterCoder from './FilterCoder'
import FinishableOutputStream from './FinishableOutputStream'
import ArrayCache from './ArrayCache'
import Long from "../../util/long/index"

export default interface FilterEncoder extends FilterCoder {
    getFilterID(): Long;

    getFilterProps(): Int8Array;

    supportsFlushing(): boolean;

    getOutputStream(finishable: FinishableOutputStream, arrayCache: ArrayCache): FinishableOutputStream;
}
