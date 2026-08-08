import Foundation

/// Reads a bundled asset's contents out of the app bundle, rather than
/// baking it into a Swift string literal. Two kinds of caller use this:
///
/// - `HighlightJS`/`HighlightJSTheme`: third-party, vendored at build time
///   by `scripts/vendor-highlightjs.sh` (`make vendor`) into
///   `Sources/Folium/Vendor/` (gitignored) from the pinned version in
///   `vendor/package.json`.
/// - `GitHubStylesheet`/`CodeBlockStylesheet`/`CodeBlockScript`: first-party,
///   authored directly as real `.css`/`.js` files under
///   `Sources/Folium/Resources/` and committed like any other source file —
///   no build step needed, just real editor tooling instead of CSS/JS
///   trapped inside a Swift string.
///
/// Either way, `Package.swift` declares the containing directory as a
/// resource so SPM bundles it, and this reads it back at first access.
enum BundledAsset {
    /// - Parameters:
    ///   - resource: The file's base name, e.g. `"highlight.min"`.
    ///   - extension: The file's extension, e.g. `"js"`.
    ///   - subdirectory: Path within the resource bundle, e.g. `"HighlightJS"`.
    ///     Note this is relative to the bundle root by the *copied
    ///     directory's own name*, not its full path under `Sources/Folium/`:
    ///     a `resources: [.copy("Vendor/HighlightJS")]` entry in
    ///     `Package.swift` lands at `HighlightJS` in the bundle, not
    ///     `Vendor/HighlightJS`.
    static func contents(
        resource: String,
        extension fileExtension: String,
        subdirectory: String,
        bundle: Bundle = .module
    ) -> String {
        let missing = "Missing bundled asset \(subdirectory)/\(resource).\(fileExtension) — run `make vendor` first."
        // Only unreachable on a broken build setup (e.g. `make vendor` hasn't
        // run for the vendored assets), not any input a test can exercise —
        // see MarkdownRenderer for the same one-line-guard convention and why.
        guard let value = load(resource, fileExtension, subdirectory, bundle) else { fatalError(missing) }
        return value
    }

    private static func load(_ resource: String, _ ext: String, _ dir: String, _ bundle: Bundle) -> String? {
        guard let url = bundle.url(forResource: resource, withExtension: ext, subdirectory: dir) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
