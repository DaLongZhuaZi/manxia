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

export default class Dirent {
    public ino: int;
    public parentIno: int;
    public typeFiled: int;
    public name: string;

    constructor(ino: int, parentIno: int, typeFiled: int, name: string) {
        this.ino = ino;
        this.parentIno = parentIno;
        this.typeFiled = typeFiled;
        this.name = name;
    }

    getIno(): int {
        return this.ino;
    }

    getParentIno(): int {
        return this.parentIno;
    }

    getType(): int {
        return this.typeFiled;
    }

    getName(): string {
        return this.name;
    }

    public toString(): string  {
        return [this.ino, this.name].join(':');
    }
}