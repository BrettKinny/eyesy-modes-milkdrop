# Third-party notices

This pack's own code is under the BSD 3-Clause License in [LICENSE](LICENSE).
Some fragments port shader code or constructs from other projects, under the
licenses below. Each fragment's header names its source.

## MilkDrop 2 (Nullsoft)

`milkdrop/frag/warp_default.frag` ports MilkDrop 2's default `warp_ps.fx`, and
`milkdrop/frag/blur1.frag` ports its `blur1_ps.fx`, as distributed in
[milkdrop2077/MilkDrop3](https://github.com/milkdrop2077/MilkDrop3)
(`code/resources/Milkdrop2`). That code is distributed under this license:

```text
Copyright 2005-2013 Nullsoft, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

  * Redistributions of source code must retain the above copyright notice,
    this list of conditions and the following disclaimer.

  * Redistributions in binary form must reproduce the above copyright notice,
    this list of conditions and the following disclaimer in the documentation
    and/or other materials provided with the distribution.

  * Neither the name of Nullsoft nor the names of its contributors may be used to
    endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER
IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## MIT-licensed shader sources

These fragments port a construct (not a whole file) from MIT-licensed code:

| Fragment | Source | Copyright |
| --- | --- | --- |
| `milkdrop/frag/comp_plasma.frag` | [maravexa/hyprsaver](https://github.com/maravexa/hyprsaver) `shaders/plasma.frag` | Copyright (c) 2026 Mara Vexa |
| `milkdrop/frag/warp_kaleido.frag` | [three.js](https://github.com/mrdoob/three.js) `examples/jsm/shaders/KaleidoShader.js` | Copyright © 2010-2026 three.js authors |
| `milkdrop/frag/comp_rotoblur.frag` | [gl-transitions](https://github.com/gl-transitions/gl-transitions) `tangentMotionBlur.glsl` (author: chenkai), with three.js `AfterimageShader.js` | Copyright (c) 2017-present gl-transitions contributors; Copyright © 2010-2026 three.js authors |
| `milkdrop/frag/comp_softmax.frag` | [jamieowen/glsl-blend](https://github.com/jamieowen/glsl-blend) `screen.glsl` | Copyright (c) 2015 Jamie Owen |

Each is distributed under the MIT License:

```text
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Trademarks

MilkDrop was created by Ryan Geiss and Nullsoft. EYESY is a trademark of Critter
& Guitari, Inc. This project is independent. It is not affiliated with, endorsed
by, or supported by Nullsoft, the MilkDrop authors, or Critter & Guitari.
