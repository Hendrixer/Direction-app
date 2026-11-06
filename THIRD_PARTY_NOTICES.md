# Third-party notices

Direction uses the following relevant open-source libraries, resolved in Package.resolved:

- [GRDB.swift](https://github.com/groue/GRDB.swift), 7.11.1: SQLite transactions, concurrent access, and project persistence. MIT license; copyright Gwendal Roué and contributors.
- [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk), 0.12.1: official local MCP transport, server dispatch, and multimodal tool responses. Repository licenses are MIT and Apache-2.0 as applicable to contributions; see its LICENSE and NOTICE files.
- [Swift Argument Parser](https://github.com/apple/swift-argument-parser), 1.8.2: typed command-line commands and help. Apache-2.0 with Swift Runtime Library Exception; copyright Apple Inc. and contributors.
- [Sparkle](https://github.com/sparkle-project/Sparkle), 2.10.1: updates for the signed copies. MIT license, with notices for the code it includes (bsdiff, ed25519 and others) in its LICENSE file; copyright Andy Matuschak, the Sparkle Project contributors and others. The packaging script copies that file into the app's resources.
- [Sentry for Apple platforms](https://github.com/getsentry/sentry-cocoa), 9.33.0 (its static `Sentry.xcframework`, checked against the release's checksum): crash and error reports, sent only when the person turns them on. MIT license; copyright Sentry. Its license is in `Resources/Licenses/sentry-cocoa/LICENSE.md`, which the packaging script copies into the app's resources.

Direction doesn't ship [yt-dlp](https://github.com/yt-dlp/yt-dlp) (the Unlicense, public domain). The first time someone gives Direction a video link, it downloads yt-dlp's macOS build from yt-dlp's GitHub releases, checks it against the checksums published with the release, and keeps it in `~/Library/Application Support/Direction/Tools/`.

The MCP SDK also brings Swift NIO, Swift Atomics, Swift Collections, Swift System, Swift Log, and EventSource as transitive dependencies. Their complete source and license notices are in the corresponding SwiftPM checkouts. The packaging script copies their upstream license files into the app's resources.

The interface bundles [Archivo](https://github.com/google/fonts/tree/main/ofl/archivo), a variable typeface by Omnibus-Type, under the SIL Open Font License 1.1. The original font and license are included in the app's resource bundle; registration is limited to the app process.

Apple system frameworks perform media decoding, Metal/Core Image rendering, audio processing, and local speech recognition. FFmpeg is not an application or test dependency.

## Graphics libraries

Graphics (`docs/graphics.md`) bundle four JavaScript libraries, minified and unmodified, for pages the editor writes. They run offline inside Direction's renderer as `direction:lib/<name>.js`. Their license texts also ship beside them in the DirectionMedia resource bundle (`Web/lib/licenses/`). GSAP is not bundled.

- [anime.js](https://github.com/juliangarnier/anime) 4.5.0, `dist/bundles/anime.umd.min.js` from npm `animejs@4.5.0`. MIT license; Copyright (c) 2025 Julian Garnier.
- [d3](https://github.com/d3/d3) 7.9.0, `dist/d3.min.js` from npm `d3@7.9.0`. ISC license; Copyright 2010-2023 Mike Bostock.
- [three.js](https://github.com/mrdoob/three.js) 0.186.1 (r186), from npm `three@0.186.1`. MIT license; Copyright © 2010-2026 three.js authors. three.js publishes ES modules only, so its `build/three.module.js` is bundled with esbuild 0.25.10 into one classic script (`three.js`, global `THREE`) and one ES module (`three.module.js`), minified; the code is unchanged.
- [lottie-web](https://github.com/airbnb/lottie-web) 5.13.0, `build/player/lottie.min.js` from npm `lottie-web@5.13.0`. MIT license; Copyright (c) 2015 Bodymovin.

The graphics renderer also bundles its own copy of Archivo (above) for pages to use, under the same SIL Open Font License 1.1, with the license beside it (`Web/fonts/Archivo-OFL.txt`).

### MIT License (anime.js, three.js, lottie-web)

Copyright (c) 2025 Julian Garnier · Copyright © 2010-2026 three.js authors · Copyright (c) 2015 Bodymovin

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

### ISC License (d3)

Copyright 2010-2023 Mike Bostock

Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
