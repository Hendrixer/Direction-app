# Third-party notices

Direction uses the following relevant open-source libraries, resolved in Package.resolved:

- [GRDB.swift](https://github.com/groue/GRDB.swift), 7.11.1: SQLite transactions, concurrent access, and project persistence. MIT license; copyright Gwendal Roué and contributors.
- [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk), 0.12.1: official local MCP transport, server dispatch, and multimodal tool responses. Repository licenses are MIT and Apache-2.0 as applicable to contributions; see its LICENSE and NOTICE files.
- [Swift Argument Parser](https://github.com/apple/swift-argument-parser), 1.8.2: typed command-line commands and help. Apache-2.0 with Swift Runtime Library Exception; copyright Apple Inc. and contributors.

The MCP SDK also brings Swift NIO, Swift Atomics, Swift Collections, Swift System, Swift Log, and EventSource as transitive dependencies. Their complete source and license notices are in the corresponding SwiftPM checkouts. The packaging script copies their upstream license files into the app's resources.

The interface bundles [Archivo](https://github.com/google/fonts/tree/main/ofl/archivo), a variable typeface by Omnibus-Type, under the SIL Open Font License 1.1. The original font and license are included in the app's resource bundle; registration is limited to the app process.

Apple system frameworks perform media decoding, Metal/Core Image rendering, audio processing, and local speech recognition. FFmpeg is not an application or test dependency.
