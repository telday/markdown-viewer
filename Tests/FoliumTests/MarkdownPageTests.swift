import Foundation
import Testing
@testable import Folium

struct MarkdownPageTests {
    // MARK: - resourceBaseURL

    @Test func resourceBaseURLPointsAtFoliumsOwnBundle() {
        // MarkdownWebView must resolve the shell's relative <link>/<script
        // src> references — and the loadFileURL read-access grant — against
        // this. Drift here (e.g. back to the wrong `resourceURL` property,
        // which points at a nonexistent path) would silently unstyle the
        // whole app. Under the test runner the resolution takes its fallback
        // branch, so this also proves the fallback yields a usable base.
        #expect(MarkdownPage.resourceBaseURL.isFileURL)
        #expect(MarkdownPage.resourceBaseURL.lastPathComponent.hasSuffix(".bundle"))
    }

    @Test func strictPageURLPointsAtTheRealShellFile() {
        #expect(MarkdownPage.strictPageURL.lastPathComponent == "page.html")
        #expect(FileManager.default.fileExists(atPath: MarkdownPage.strictPageURL.path))
    }

    // MARK: - shellURL(remoteContentAllowed:) — issue #19

    @Test func remotePageURLPointsAtTheRealOptInShellFile() {
        #expect(MarkdownPage.remotePageURL.lastPathComponent == "page-remote.html")
        #expect(FileManager.default.fileExists(atPath: MarkdownPage.remotePageURL.path))
    }

    @Test func shellURLSelectionStaysStrictByDefault() {
        #expect(MarkdownPage.shellURL(remoteContentAllowed: false) == MarkdownPage.strictPageURL)
    }

    @Test func shellURLSelectionSwitchesToTheOptInShellWhenAllowed() {
        #expect(MarkdownPage.shellURL(remoteContentAllowed: true) == MarkdownPage.remotePageURL)
    }

    // MARK: - Shell drift guard — issue #19

    @Test func theTwoShellsDifferOnlyInTheCSPMetaLine() throws {
        // Two hand-maintained near-copies of the shell is the real risk
        // issue #19 takes on by not making the CSP mutable. This is the
        // test that makes that acceptable: any edit to page.html that isn't
        // mirrored into page-remote.html (or vice versa) fails here, in
        // something more precise than "the diff looked large."
        let strictLines = try String(contentsOf: MarkdownPage.strictPageURL, encoding: .utf8)
            .components(separatedBy: .newlines)
        let remoteLines = try String(contentsOf: MarkdownPage.remotePageURL, encoding: .utf8)
            .components(separatedBy: .newlines)

        let cspPrefix = #"<meta http-equiv="Content-Security-Policy""#

        // The header <!-- ... --> comment above the CSP meta tag is not part
        // of this comparison: it explains *that* shell's own policy, so its
        // wording is only accurate on the file it's written on and is
        // expected to differ between the two — see page-remote.html's own
        // comment for why it isn't page.html's, word for word. What this
        // guard actually protects starts at the CSP meta line: every other
        // directive, and every asset tag below it, has to stay identical.
        let strictCSPIndex = try #require(
            strictLines.firstIndex { $0.hasPrefix(cspPrefix) }, "no CSP meta line found in page.html"
        )
        let remoteCSPIndex = try #require(
            remoteLines.firstIndex { $0.hasPrefix(cspPrefix) }, "no CSP meta line found in page-remote.html"
        )
        let strictTail = strictLines[strictCSPIndex...]
        let remoteTail = remoteLines[remoteCSPIndex...]

        #expect(strictTail.count == remoteTail.count)

        var sawCSPLineDiffer = false
        for (strictLine, remoteLine) in zip(strictTail, remoteTail) where strictLine != remoteLine {
            let bothAreCSPLines = strictLine.hasPrefix(cspPrefix) && remoteLine.hasPrefix(cspPrefix)
            #expect(bothAreCSPLines, "unexpected drift outside the CSP line: \(strictLine) vs \(remoteLine)")
            sawCSPLineDiffer = true
        }
        #expect(sawCSPLineDiffer, "expected the CSP line itself to differ between the two shells")
    }

    @Test func remoteShellRelaxesOnlyImgAndMediaSrcToAlsoAdmitHTTPS() throws {
        let cspContent = try cspDirectiveString(of: MarkdownPage.remotePageURL)

        // Never 'self' — see page.html's own doc comment on why that keyword
        // leaks https on a file:// page. And never http:, per issue #19's
        // decision that cleartext content stays blocked even after opt-in.
        // Isolated to the directive string, not the whole file: the doc
        // comment above the meta tag quotes both tokens by name while
        // explaining the choice, and a whole-file check would trip over its
        // own explanation the same way shellDeclaresACSPThatEnforcesThe
        // NoNetworkFloor's does.
        #expect(!cspContent.contains("'self'"))
        #expect(!cspContent.contains("http:"))

        #expect(cspContent.contains("img-src file: https:;"))
        #expect(cspContent.contains("media-src file: https:;"))
        // Every other fetch directive is untouched.
        #expect(cspContent.contains("script-src file:;"))
        #expect(cspContent.contains("style-src file:;"))
        #expect(cspContent.contains("font-src file:;"))
    }

    /// Extracts just the `content="…"` value of the CSP `<meta>` tag from
    /// `pageURL`'s file — the directive string itself, not the surrounding
    /// doc comment that quotes CSP fragments (like `'self'`) by name while
    /// explaining them.
    private func cspDirectiveString(of pageURL: URL) throws -> String {
        let shell = try String(contentsOf: pageURL, encoding: .utf8)
        let openTag = #"<meta http-equiv="Content-Security-Policy" content=""#
        let cspOpen = try #require(shell.range(of: openTag))
        let cspClose = try #require(shell.range(of: "\">", range: cspOpen.upperBound..<shell.endIndex))
        return String(shell[cspOpen.upperBound..<cspClose.lowerBound])
    }

    @Test func shellReferencesEveryAssetByURLWithNoCDNReference() throws {
        let shell = try String(contentsOf: MarkdownPage.strictPageURL, encoding: .utf8)

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
        let shell = try String(contentsOf: MarkdownPage.strictPageURL, encoding: .utf8)
        // WKWebView needs this to report the system light/dark setting.
        #expect(shell.contains(#"<meta name="color-scheme" content="light dark">"#))
    }

    @Test func shellDeclaresACSPThatEnforcesTheNoNetworkFloor() throws {
        let shell = try String(contentsOf: MarkdownPage.strictPageURL, encoding: .utf8)

        let openTag = #"<meta http-equiv="Content-Security-Policy" content=""#
        guard let cspOpen = shell.range(of: openTag),
              let cspClose = shell.range(of: "\">", range: cspOpen.upperBound..<shell.endIndex) else {
            Issue.record("No CSP meta tag found in page.html")
            return
        }
        // Isolated to just the directive string, not the whole file: the
        // surrounding doc comment quotes CSP fragments like `script-src file:`
        // by name while explaining the choice, and a whole-file substring
        // check would trip over its own explanation.
        let cspContent = String(shell[cspOpen.upperBound..<cspClose.lowerBound])

        // Every asset tag must load under a policy that's already in force —
        // a CSP appended after them would leave a window where nothing
        // polices the very tags issue #17 exists to police. Searched only
        // after the meta tag closes, not from the top of the file: the doc
        // comment above the meta tag itself quotes `<link rel="stylesheet">`
        // by name, and a whole-file search would match that mention instead.
        let firstAssetTag = shell.range(of: "<link rel=\"stylesheet\"", range: cspClose.upperBound..<shell.endIndex)
        #expect(firstAssetTag != nil)

        // Every fetch directive uses the unquoted scheme-source `file:`, not
        // `'self'` — see the comment in page.html: `'self'` was measured to
        // still admit a cross-origin `https://` load on this `file://` page,
        // which `file:` does not. Verified in `ContentSecurityPolicyTests.swift`.
        let directives = [
            "default-src 'none'",
            "script-src file:",
            "style-src file:",
            "img-src file:",
            "font-src file:",
            "media-src file:",
            "base-uri 'none'",
            "form-action 'none'"
        ]
        for directive in directives {
            #expect(cspContent.contains(directive), "missing CSP directive: \(directive)")
        }
        // The whole point of this CSP: no directive may use 'self', which
        // was found not to restrict http(s) sources on this file:// page.
        #expect(!cspContent.contains("'self'"))
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

    // MARK: - scrollToAnchorScript

    @Test func rendersToAFoliumScrollToAnchorCall() {
        let script = MarkdownPage.scrollToAnchorScript("usage")

        #expect(script == #"window.FoliumScrollToAnchor("usage")"#)
    }

    @Test func safelyEscapesAFragmentContainingQuotesAndBackslashesForJSInjection() {
        // The fragment comes straight off a URL in rendered document content,
        // so it's attacker-controlled the same way renderBodyScript's HTML
        // is — an unescaped quote or backslash must not be able to break out
        // of the JS string literal it's injected into.
        let script = MarkdownPage.scrollToAnchorScript(#"a"b\c"#)

        #expect(script.contains(#"a\"b\\c"#))
        #expect(!script.contains(#""a"b\c""#))
    }
}
