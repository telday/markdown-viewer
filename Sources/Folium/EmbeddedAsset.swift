/// Decodes a `PackageResources` byte array (from an `.embedInCode` resource
/// — see `GitHubStylesheet`) as UTF-8. `String(bytes:encoding:)` rather than
/// `String(decoding:as:)`: the latter never fails, silently substituting the
/// replacement character for invalid bytes, which would mask a genuinely
/// corrupt asset instead of surfacing it.
enum EmbeddedAsset {
    static func string(_ bytes: [UInt8]) -> String {
        // Only unreachable for a genuinely non-UTF-8 embedded file, not any
        // input a test can exercise — see MarkdownRenderer for the same
        // one-line-guard convention and why.
        guard let value = String(bytes: bytes, encoding: .utf8) else { fatalError("Embedded asset isn't valid UTF-8.") }
        return value
    }
}
