import Foundation
import Testing
@testable import Folium

struct MarkdownPageTests {
    @Test func resourceBaseURLPointsAtFoliumsOwnBundle() {
        // MarkdownWebView must resolve the shell's relative <link>/<script
        // src> references — and the loadFileURL read-access grant — against
        // this. Drift here (e.g. back to the wrong `resourceURL` property,
        // which points at a nonexistent path) would silently unstyle the
        // whole app.
        #expect(MarkdownPage.resourceBaseURL.isFileURL)
        #expect(MarkdownPage.resourceBaseURL.lastPathComponent.hasSuffix(".bundle"))
    }

    @Test func pageURLPointsAtTheRealShellFile() {
        #expect(MarkdownPage.pageURL.lastPathComponent == "page.html")
        #expect(FileManager.default.fileExists(atPath: MarkdownPage.pageURL.path))
    }

    @Test func shellReferencesEveryAssetByURLWithNoCDNReference() throws {
        let shell = try String(contentsOf: MarkdownPage.pageURL, encoding: .utf8)

        #expect(shell.contains(#"<link rel="stylesheet" href="github.css">"#))
        #expect(shell.contains(#"href="../HighlightJS/styles/github.min.css" media="(prefers-color-scheme: light)""#))
        let darkThemeLink = #"href="../HighlightJS/styles/github-dark.min.css" media="(prefers-color-scheme: dark)""#
        #expect(shell.contains(darkThemeLink))
        #expect(shell.contains(#"<link rel="stylesheet" href="code-block.css">"#))
        #expect(shell.contains(#"<script src="../HighlightJS/highlight.min.js"></script>"#))
        #expect(shell.contains(#"<script src="code-block.js"></script>"#))
        // Defines window.FoliumScrollBy, which scrollScript calls.
        #expect(shell.contains(#"<script src="scroll.js"></script>"#))
        // The container renderBodyScript's window.FoliumRenderBody targets.
        #expect(shell.contains(#"<article class="markdown-body" id="markdown-content"></article>"#))
        // Vendored locally, loaded from the app's own bundle: every asset
        // reference is a bundle-relative path, never an absolute http(s) URL.
        #expect(!shell.contains("http://"))
        #expect(!shell.contains("https://"))
        #expect(!shell.contains("cdn"))
    }

    @Test func shellDeclaresSystemColorScheme() throws {
        let shell = try String(contentsOf: MarkdownPage.pageURL, encoding: .utf8)
        // WKWebView needs this to report the system light/dark setting.
        #expect(shell.contains(#"<meta name="color-scheme" content="light dark">"#))
    }

    // MARK: - renderBodyScript

    @Test func rendersToAFoliumRenderBodyCall() {
        let script = MarkdownPage.renderBodyScript(bodyHTML: "<p>hi</p>")

        #expect(script.hasPrefix(#"window.FoliumRenderBody(""#))
        #expect(script.hasSuffix(#"")"#))
        // JSONEncoder also escapes "/" as "\/" (a JSON convention, harmless
        // here, that avoids "</script>" prematurely closing an embedding
        // <script> tag) — closing tags come through with an escaped slash.
        #expect(script.contains(#"<p>hi<\/p>"#))
    }

    @Test func safelyEscapesContentForJSInjection() {
        // JSON-encoded, so an embedded quote is escaped rather than
        // terminating the JS string literal early — a real injection risk
        // if a Markdown document's rendered HTML happened to contain one.
        let script = MarkdownPage.renderBodyScript(bodyHTML: #"<p>She said "hi"</p>"#)

        #expect(script.contains(#"She said \"hi\""#))
        #expect(!script.contains(#"said "hi""#))
    }

    @Test func decoratesCodeBlocksBeforeInjecting() {
        let bodyHTML = #"<pre><code class="language-swift">let x = 1\n</code></pre>"#
        let script = MarkdownPage.renderBodyScript(bodyHTML: bodyHTML)

        // The full pipeline runs the body through CodeBlockDecorator, not
        // just a literal pass-through — drift here would silently ship
        // fenced code with no chrome at all. Quotes are JSON-escaped (this
        // is embedded in a JS string literal) and closing tags carry a
        // JSON-escaped "\/" — see rendersToAFoliumRenderBodyCall.
        #expect(script.contains(#"class=\"code-block\""#))
        #expect(script.contains(#"<span class=\"code-block-lang\">swift<\/span>"#))
        #expect(script.contains(#"<button type=\"button\" class=\"copy-button\">Copy<\/button>"#))
    }

    // MARK: - scrollScript

    @Test func scrollsTheDocumentTheWayTheKeyPointed() {
        // Sign is the whole contract between Swift and window.FoliumScrollBy:
        // the two are otherwise indistinguishable, and getting it backwards is
        // the kind of bug nothing else here would catch.
        #expect(MarkdownPage.scrollScript(.downward) == "window.FoliumScrollBy(3)")
        #expect(MarkdownPage.scrollScript(.upward) == "window.FoliumScrollBy(-3)")
    }

    @Test func scrollJSTakesItsStepInLinesSoTextZoomCarriesThrough() throws {
        let scrollJS = try String(
            contentsOf: MarkdownPage.resourceBaseURL.appendingPathComponent("Resources/scroll.js"),
            encoding: .utf8
        )

        // A pixel step baked into the Swift side would stop meaning "a few
        // lines" the moment the user pressed ⌘+.
        #expect(scrollJS.contains("lineHeight"))
        // Smooth motion is an acceptance criterion of issue #6, and it is one
        // option string away from being a jump.
        #expect(scrollJS.contains(#"behavior: "smooth""#))
        // Native capture, not a page-side listener — also an acceptance
        // criterion, and cheap to regress by "just adding a listener here".
        #expect(!scrollJS.contains("addEventListener"))
    }
}
