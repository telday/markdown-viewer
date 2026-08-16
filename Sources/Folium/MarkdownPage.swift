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
    /// Where the shell sits inside whichever base wins below. Its CSS and JS
    /// sit beside it at the same relative paths wherever it is, so the base
    /// is the only thing left to choose.
    static let pageRelativePath = "Resources/page.html"

    /// Picks the directory the shell and its assets are read from: the first
    /// candidate that holds the shell, or `fallback` when none does.
    ///
    /// The question asked is "is the shell here?", not "am I running inside
    /// an app?". An installed app and a test run take the same path through
    /// this code, with different inputs. The caller supplies the live
    /// `Bundle` values, which is what lets a unit test reach this.
    ///
    /// `fallback` is `@autoclosure` so it is only evaluated if it is used.
    /// The Swift Package Manager (SPM) generates the `Bundle.module`
    /// accessor, and that accessor crashes when its resource bundle is
    /// missing. An app carrying its own resources never needs the fallback,
    /// and must not crash reaching for it.
    static func resolveResourceBase(
        candidates: [URL],
        fallback: @autoclosure () -> URL,
        fileExists: (URL) -> Bool
    ) -> URL {
        candidates.first { fileExists($0.appendingPathComponent(pageRelativePath)) } ?? fallback()
    }

    /// The base URL `page.html`'s relative `<link>`/`<script src>`
    /// references resolve against, and the read-access grant
    /// `MarkdownWebView` passes to `loadFileURL`.
    ///
    /// A Mac app keeps files like these in `Contents/Resources`, which is
    /// what `Bundle.main.resourceURL` names and the only place a code
    /// signature can seal them. That wins when the shell is found there.
    ///
    /// `swift run` and `swift test` assemble no `.app`, so they fall through
    /// to the resource bundle SPM generates. That one is reached by
    /// `bundleURL`, not `resourceURL`: SPM's bundle is flat, with no
    /// `Contents/Resources` inside it, and `resourceURL` would point at a
    /// path that isn't there.
    ///
    /// Exposed here, rather than used inline in `MarkdownWebView`, because
    /// tests that load the shell need the same value. A test file cannot
    /// name `Bundle.module` itself — that is ambiguous once the test target
    /// has its own resources and also `@testable import`s Folium.
    static let resourceBaseURL = resolveResourceBase(
        candidates: [Bundle.main.resourceURL].compactMap { $0 },
        fallback: Bundle.module.bundleURL,
        fileExists: { FileManager.default.fileExists(atPath: $0.path) }
    )

    /// The static page shell `MarkdownWebView` loads once via `loadFileURL`.
    static let pageURL = resourceBaseURL.appendingPathComponent(pageRelativePath)

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

    /// How far one press of a scroll key moves the document, in lines of body
    /// text. `Resources/scroll.js` turns lines into pixels against the
    /// document's own line height, so the step keeps its meaning as the user
    /// zooms the text (⌘+/⌘−).
    ///
    /// Three rather than vim's one: `j` in vim moves a cursor that the reader
    /// is watching, while here there is nothing to follow, and a one-line step
    /// makes a long document feel stuck.
    static let scrollLinesPerPress = 3

    /// Builds the `evaluateJavaScript` call that scrolls the document one key
    /// press, via `window.FoliumScrollBy` — defined by `Resources/scroll.js`.
    static func scrollScript(_ direction: ScrollDirection) -> String {
        let lines = direction == .downward ? scrollLinesPerPress : -scrollLinesPerPress
        return "window.FoliumScrollBy(\(lines))"
    }
}
