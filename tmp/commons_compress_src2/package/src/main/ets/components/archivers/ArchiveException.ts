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
import Exception from '../util/Exception';
import Long from "../util/long/index";


export default class ArchiveException extends Exception {
    static readonly kind: string = 'ArchiveException';
    private static readonly serialVersionUID: Long = Long.fromString('2772690708123267100');

    constructor(message: string, cause: Exception) {
        super(message);
    }
}