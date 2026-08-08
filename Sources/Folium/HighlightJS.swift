/// highlight.js — syntax highlighting for fenced code blocks (issue #4).
/// Upstream: https://github.com/highlightjs/highlight.js, via the
/// `@highlightjs/cdn-assets` package (the same prebuilt bundle CDNs serve).
/// No CDN dependency at runtime: `VendoredAsset` reads the file
/// `scripts/vendor-highlightjs.sh` copies into the app bundle at build time
/// from the version pinned in `vendor/package.json`. License: BSD-3-Clause
/// — see THIRD_PARTY_LICENSES.md.
enum HighlightJS {
    /// The "common languages" bundle: core + ~40 widely used languages
    /// (bash, c, cpp, csharp, css, go, java, javascript, json, kotlin, php,
    /// python, ruby, rust, shell, sql, swift, typescript, xml, yaml, and more).
    ///
    /// Subdirectory is "HighlightJS", not "Vendor/HighlightJS": SPM's
    /// `.copy("Vendor/HighlightJS")` resource places the copied directory at
    /// the bundle root by its own basename, dropping the source-side prefix.
    static let script = BundledAsset.contents(
        resource: "highlight.min",
        extension: "js",
        subdirectory: "HighlightJS"
    )
}
