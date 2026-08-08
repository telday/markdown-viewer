/// Runtime wiring for fenced code blocks (issue #4): runs highlight.js over
/// every code block, and gives each `.copy-button` (added by
/// `CodeBlockDecorator`) a click handler that copies the block's raw text
/// and shows brief "Copied!" confirmation.
///
/// Placed in a `<script>` right after the rendered article, so the DOM it
/// operates on already exists by the time it runs — no `DOMContentLoaded`
/// wait needed. Copies via `document.execCommand("copy")` rather than the
/// async Clipboard API: `MarkdownWebView` loads content with
/// `loadHTMLString(_:baseURL: nil)`, which WebKit treats as an opaque origin,
/// and `navigator.clipboard` is unavailable there — there's no secure-context
/// path to fall back from.
///
/// Authored as a real file (`Sources/Folium/Resources/code-block.js`, read
/// via `BundledAsset`) rather than a Swift string literal — see
/// `GitHubStylesheet` for why.
enum CodeBlockScript {
    static let script = BundledAsset.contents(resource: "code-block", extension: "js", subdirectory: "Resources")
}
