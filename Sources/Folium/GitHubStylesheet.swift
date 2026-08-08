/// The base stylesheet that makes rendered Markdown visually match GitHub's own
/// rendering (issue #3): typography, spacing, tables, lists, blockquotes, images,
/// horizontal rules, and links. Adapted from GitHub's open-source
/// `github-markdown-css` (Primer color tokens).
///
/// Colors follow the *system* appearance: the light palette lives on `:root`
/// and a `prefers-color-scheme: dark` block swaps in the dark palette, so the
/// rendered document tracks macOS light/dark automatically (the host page also
/// declares `<meta name="color-scheme" content="light dark">` so WKWebView
/// honors the system setting).
///
/// Authored as a real file (`Sources/Folium/Resources/github.css`, read via
/// `BundledAsset`) rather than a Swift string literal, so it gets real CSS
/// editor tooling instead of living inside `.swift` source.
enum GitHubStylesheet {
    static let css = BundledAsset.contents(resource: "github", extension: "css", subdirectory: "Resources")
}
