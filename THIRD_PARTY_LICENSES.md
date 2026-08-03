# Third-party licenses

Folium vendors the following third-party assets so there's no CDN dependency
at runtime (see `docs/agents/definition-of-done.md` and issue #4).

## highlight.js

- **Source**: https://github.com/highlightjs/highlight.js
- **Pinned version**: `vendor/package.json` (kept current via Dependabot —
  see that file's `//` key and `.github/dependabot.yml`)
- **Vendored as**: `scripts/vendor-highlightjs.sh` (`make vendor`, a
  prerequisite of `build`/`test`/`coverage`) copies the "common languages"
  bundle and the `github`/`github-dark` themes from `@highlightjs/cdn-assets`
  into `Sources/Folium/Vendor/HighlightJS/` at build time, unmodified. That
  directory is gitignored — the actual bytes live only in the npm registry
  and each build's output, not in this repo; `Sources/Folium/HighlightJS.swift`
  / `HighlightJSTheme.swift` read them via `VendoredAsset` + SPM resources.
- **License**: BSD 3-Clause

```
BSD 3-Clause License

Copyright (c) 2006, Ivan Sagalaev.
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

* Neither the name of the copyright holder nor the names of its
  contributors may be used to endorse or promote products derived from
  this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```
