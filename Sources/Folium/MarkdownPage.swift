import Foundation

/// Locates `MarkdownWebView`'s static page shell (`Resources/page.html`) and
/// builds the JS call that injects a freshly rendered Markdown body into it.
///
/// The shell references its own CSS/JS by real `<link>`/`<script src>` URLs
/// — the way any webpage loads its assets — rather than inlining their
/// content into a Swift string. `Sources/Folium/Resources/` (first-party)
/// and `Sources/Folium/Vendor/HighlightJS/` (vendored, see
/// `scripts/vendor-highlightjs.sh`) are both declared as `.copy` resources
/// in `Package.swift`, so they exist as real files at those bundle-relative
/// paths at runtime.
///
/// `MarkdownWebView` loads the shell exactly once per `WKWebView` (via
/// `loadFileURL`, which — unlike `loadHTMLString` — actually grants the page
/// read access to those sibling files); every content update after that is
/// a `renderBodyScript` call via `evaluateJavaScript`, not a reload. See
/// `MarkdownWebViewState` for why: a full reload would re-parse every
/// stylesheet and re-parse/recompile all of highlight.js on every change.
///
/// This is plain string/URL assembly with no WebKit/AppKit dependency, so it
/// lives in the unit-testable logic layer rather than in `MarkdownWebView`
/// glue.
enum MarkdownPage {
    /// The base URL `page.html`'s relative `<link>`/`<script src>`
    /// references resolve against, and the read-access grant
    /// `MarkdownWebView` passes to `loadFileURL`: Folium's own resource
    /// bundle. `bundleURL`, not `resourceURL` — the latter assumes a
    /// `Contents/Resources` substructure that SPM's flat, loose resource
    /// bundles don't have, and silently points at a nonexistent path
    /// (`Folium_Folium.bundle/Resources/`) instead.
    ///
    /// Exposed here (not just used inline in `MarkdownWebView`) because
    /// tests that load the shell outside `MarkdownWebView` need the same
    /// value — referencing `Bundle.module` directly from a test file is
    /// ambiguous once that test target has its own resources and also
    /// `@testable import`s Folium.
    static let resourceBaseURL = Bundle.module.bundleURL

    /// The static page shell `MarkdownWebView` loads once via `loadFileURL`.
    static let pageURL = resourceBaseURL.appendingPathComponent("Resources/page.html")

    /// Builds the `evaluateJavaScript` call that renders `bodyHTML` (run
    /// through `CodeBlockDecorator` first) into the already-loaded shell's
    /// `#markdown-content` container, via `window.FoliumRenderBody` —
    /// defined by `Resources/code-block.js`.
    static func renderBodyScript(bodyHTML: String) -> String {
        let decorated = CodeBlockDecorator.decorate(bodyHTML)
        // Only unreachable for a String that can't round-trip as JSON, which
        // cmark's UTF-8 HTML output always can — not any input a test can
        // exercise. JSON string syntax is valid JS string syntax, so this
        // also handles escaping quotes/newlines/etc. for the injection safely.
        let failure = "Failed to JSON-encode rendered Markdown for JS injection."
        guard let json = try? JSONEncoder().encode(decorated) else { fatalError(failure) }
        guard let jsString = String(data: json, encoding: .utf8) else { fatalError(failure) }
        return "window.FoliumRenderBody(\(jsString))"
    }
}
