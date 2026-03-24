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
import DeltaCoder from './DeltaCoder'
import Exception from '../../util/Exception'
import InputStream from '../../util/InputStream'
import ArrayCache from './ArrayCache'
import DeltaInputStream from './DeltaInputStream'

export default class DeltaDecoder extends DeltaCoder {
    private distance: number;

    constructor(props) {
        super()
        if (props.length != 1) {
            throw new Exception("Unsupported Delta filter properties");
        } else {
            this.distance = (props[0] & 255) + 1;
        }
    }

    public getMemoryUsage(): number {
        return 1;
    }

    public getInputStream(inputStream: InputStream, arrayCache: ArrayCache): InputStream {
        return new DeltaInputStream(inputStream, this.distance);
    }
}