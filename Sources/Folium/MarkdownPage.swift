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
    /// Where the shell sits inside whichever base wins below. The assets it
    /// references sit alongside it at the same relative paths in every case,
    /// which is why choosing a base is the only decision to make.
    static let pageRelativePath = "Resources/page.html"

    /// Picks the directory the shell and its assets are read from: the first
    /// candidate that actually holds the shell, or `fallback` when none does.
    ///
    /// The probe is "is the shell here?" rather than "am I running inside an
    /// app?", so an installed app and a test run are one code path with
    /// different inputs. The live `Bundle` values are the caller's to supply,
    /// which is also what keeps this reachable from a unit test.
    ///
    /// `fallback` is `@autoclosure` because reaching for a bundle can be
    /// fatal, not merely empty: SPM's generated `Bundle.module` accessor
    /// `fatalError`s when it can't find its resource bundle. Evaluating it
    /// eagerly would crash an app that has its own resources and never needed
    /// the fallback at all.
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
    /// A Mac app keeps files like these in `Contents/Resources` — the
    /// directory `Bundle.main.resourceURL` names, and the only place a code
    /// signature can seal them — so that is what wins when the shell is found
    /// there. Nothing has assembled a `.app` during `swift run` or `swift
    /// test`, so those runs fall through to SPM's generated resource bundle:
    /// reached by `bundleURL`, not `resourceURL`, because the latter assumes
    /// a `Contents/Resources` substructure that SPM's flat, loose bundle
    /// doesn't have and silently points at a nonexistent path.
    ///
    /// Exposed here (not just used inline in `MarkdownWebView`) because
    /// tests that load the shell outside `MarkdownWebView` need the same
    /// value — referencing `Bundle.module` directly from a test file is
    /// ambiguous once that test target has its own resources and also
    /// `@testable import`s Folium.
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
