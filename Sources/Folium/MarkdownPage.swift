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

    /// The base URL `page.html`'s relative `<link>`/`<script src>`
    /// references resolve against, and the read-access grant
    /// `MarkdownWebView` passes to `loadFileURL`.
    ///
    /// A Mac app keeps files like these in `Contents/Resources`, which is
    /// what `Bundle.main.resourceURL` names and the only place a code
    /// signature can seal them. The check is for the shell itself, not for
    /// "am I inside an app": an app whose resources live elsewhere, or
    /// failed to copy, is still an app.
    ///
    /// `swift run` and `swift test` assemble no `.app` and fall through to
    /// the bundle the Swift Package Manager (SPM) generates. That one is
    /// reached by `bundleURL`, not `resourceURL`: it is flat, with no
    /// `Contents/Resources` inside it. It also comes last because SPM's
    /// generated `Bundle.module` accessor crashes, rather than returning
    /// nil, when its bundle is missing.
    ///
    /// Exposed here, rather than used inline in `MarkdownWebView`, because
    /// tests that load the shell need the same value. A test file cannot
    /// name `Bundle.module` itself — that is ambiguous once the test target
    /// has its own resources and also `@testable import`s Folium.
    static let resourceBaseURL: URL = {
        if let appResources = Bundle.main.resourceURL,
           FileManager.default.fileExists(
               atPath: appResources.appendingPathComponent(pageRelativePath).path
           ) {
            return appResources
        }
        return Bundle.module.bundleURL
    }()

    /// The static page shell `MarkdownWebView` loads once via `loadFileURL`.
    static let pageURL = resourceBaseURL.appendingPathComponent(pageRelativePath)

    /// Builds the `evaluateJavaScript` call that renders `bodyHTML` (run
    /// through `CodeBlockDecorator` first) into the already-loaded shell's
    /// `#markdown-content` container, via `window.FoliumRenderBody` —
    /// defined by `Resources/code-block.js`.
    static func renderBodyScript(bodyHTML: String) -> String {
        let decorated = CodeBlockDecorator.decorate(bodyHTML)
        return "window.FoliumRenderBody(\(jsStringLiteral(decorated)))"
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

    /// Builds the `evaluateJavaScript` call for a `NavigationDecision
    /// .scrollToAnchor` result, via `window.FoliumScrollToAnchor` — defined
    /// by `Resources/scroll.js`.
    ///
    /// The fragment comes from a URL in the rendered document, so it is
    /// attacker-controlled text the same way `renderBodyScript`'s body HTML
    /// is: JSON-encoding it, rather than interpolating it into the script
    /// string directly, is what keeps a fragment like `");window.x=1;("`
    /// from breaking out of the string literal it's injected into.
    static func scrollToAnchorScript(_ fragment: String) -> String {
        return "window.FoliumScrollToAnchor(\(jsStringLiteral(fragment)))"
    }

    /// Encodes `value` as JSON and returns the resulting bytes as a Swift
    /// `String`, which is what `renderBodyScript` and `scrollToAnchorScript`
    /// both actually need: JSON string syntax is valid JS string syntax, so
    /// the result can go straight into a `window.Foo(...)` call as a safely
    /// escaped argument — quotes, newlines, and `</script>`-closing
    /// sequences included.
    private static func jsStringLiteral(_ value: String) -> String {
        // Only unreachable for a String that can't round-trip as JSON. Never
        // true for cmark's UTF-8 HTML output or a URL fragment, so nothing a
        // test can construct reaches it.
        let failure = "Failed to JSON-encode a value for JS injection."
        guard let json = try? JSONEncoder().encode(value) else { fatalError(failure) }
        guard let jsString = String(data: json, encoding: .utf8) else { fatalError(failure) }
        return jsString
    }
}
