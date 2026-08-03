import Foundation

/// Reads a vendored third-party asset's contents out of the app bundle.
/// `HighlightJS`/`HighlightJSTheme` use this instead of a baked-in Swift
/// string literal: `scripts/vendor-highlightjs.sh` (`make vendor`, a
/// prerequisite of `build`/`test`/`coverage`) copies the actual files into
/// `Sources/Folium/Vendor/` at build time from the pinned version in
/// `vendor/package.json`, and `Package.swift` declares that directory as a
/// resource so SPM bundles it. The files are gitignored — see
/// `scripts/vendor-highlightjs.sh` for why.
enum VendoredAsset {
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
        let missing = "Missing vendored asset \(subdirectory)/\(resource).\(fileExtension) — run `make vendor` first."
        // Only unreachable if `make vendor` hasn't run, i.e. a broken build
        // setup rather than any input a test can exercise — see MarkdownRenderer
        // for the same one-line-guard convention and why.
        guard let value = load(resource, fileExtension, subdirectory, bundle) else { fatalError(missing) }
        return value
    }

    private static func load(_ resource: String, _ ext: String, _ dir: String, _ bundle: Bundle) -> String? {
        guard let url = bundle.url(forResource: resource, withExtension: ext, subdirectory: dir) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
