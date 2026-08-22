import Testing
@testable import Folium

struct RemoteContentTests {
    // MARK: - Positive: http(s) and protocol-relative

    @Test func flagsAnHTTPSImageSrc() {
        #expect(RemoteContent.isReferenced(in: #"<img src="https://example.com/badge.png">"#))
    }

    @Test func flagsAnHTTPImageSrc() {
        // http: is a blocked scheme just as much as https: — RemoteContent
        // only decides whether to show the bar; issue #19's decision that
        // http: is never unblocked lives in the two page shells, not here.
        #expect(RemoteContent.isReferenced(in: #"<img src="http://example.com/badge.png">"#))
    }

    @Test func flagsAProtocolRelativeSrc() {
        // A scheme-less "//host/…" reference inherits the page's own scheme
        // (file: here), so it would actually fail to load rather than reach
        // the network — but a document author who wrote it plainly means
        // "fetch this remotely", so the bar should still offer to load it.
        #expect(RemoteContent.isReferenced(in: #"<img src="//example.com/badge.png">"#))
    }

    @Test func flagsAnUppercaseHTTPSScheme() {
        // HTML attribute values aren't case-sensitive on the scheme, and
        // raw HTML a document embeds is user-authored, not cmark-gfm's
        // lowercase output.
        #expect(RemoteContent.isReferenced(in: #"<img src="HTTPS://example.com/badge.png">"#))
    }

    @Test func flagsARemoteURLInSrcset() {
        #expect(RemoteContent.isReferenced(in: #"<img srcset="local.png 1x, https://example.com/big.png 2x">"#))
    }

    @Test func flagsARemoteURLInPoster() {
        #expect(RemoteContent.isReferenced(in: #"<video poster="https://example.com/thumb.jpg"></video>"#))
    }

    @Test func flagsASingleQuotedRemoteSrc() {
        #expect(RemoteContent.isReferenced(in: "<img src='https://example.com/badge.png'>"))
    }

    // MARK: - Unquoted attribute values (legal HTML; live once #20 turns on raw HTML)

    @Test func flagsAnUnquotedRemoteSrc() {
        // `src=https://…` with no quotes at all is legal HTML. Unreachable
        // through cmark-gfm's safe-mode output today, but issue #20 turns on
        // CMARK_OPT_UNSAFE, which makes a document author's own raw HTML —
        // quoted or not — reach the rendered body.
        #expect(RemoteContent.isReferenced(in: "<img src=https://example.com/badge.png>"))
    }

    @Test func unquotedRemoteSrcStopsAtTheClosingAngleBracket() {
        #expect(RemoteContent.isReferenced(in: "<img src=https://example.com/badge.png>trailing text"))
    }

    @Test func unquotedRemoteSrcStopsAtWhitespaceBeforeTheNextAttribute() {
        #expect(RemoteContent.isReferenced(in: #"<img src=https://example.com/badge.png alt="badge">"#))
    }

    @Test func doesNotFlagAnUnquotedRelativePath() {
        #expect(!RemoteContent.isReferenced(in: "<img src=images/logo.png>"))
    }

    // MARK: - Negative: content #17/#18 already made safe

    @Test func doesNotFlagADataURI() {
        #expect(!RemoteContent.isReferenced(in: #"<img src="data:image/png;base64,iVBORw0KGgo=">"#))
    }

    @Test func doesNotFlagARelativePath() {
        // Issue #18 rewrites document-relative image paths to file: URLs
        // before this ever runs; a bare relative path here is local.
        #expect(!RemoteContent.isReferenced(in: #"<img src="images/logo.png">"#))
    }

    @Test func doesNotFlagAFileURL() {
        #expect(!RemoteContent.isReferenced(in: #"<img src="file:///Users/x/doc/images/logo.png">"#))
    }

    @Test func doesNotFlagPlainTextWithNoTags() {
        #expect(!RemoteContent.isReferenced(in: "just some rendered text, no markup at all"))
    }

    @Test func ignoresHrefEvenWhenItPointsRemote() {
        // A link is not loaded content — #17's navigation policy already
        // keeps clicking it from reaching the network, so it isn't this
        // type's job to flag it.
        #expect(!RemoteContent.isReferenced(in: #"<a href="https://example.com/page">link</a>"#))
    }

    // MARK: - Deliberately conservative: no HTML parsing

    @Test func flagsARemoteSrcEvenInsideAnHTMLComment() {
        // Documented, deliberate false positive: this scans text, not a
        // parsed DOM, so it can't tell a live <img> from one mentioned
        // inside a comment. An unnecessary bar is the failure mode here,
        // not a missing one — see RemoteContent.isReferenced's doc comment.
        #expect(RemoteContent.isReferenced(in: #"<!-- <img src="https://example.com/badge.png"> -->"#))
    }

    @Test func flagsARemoteSrcEvenInsideAFencedCodeBlock() {
        let codeBlock = "<pre><code>&lt;img src=\"https://example.com/badge.png\"&gt;</code></pre>"
        #expect(RemoteContent.isReferenced(in: codeBlock))
    }
}
