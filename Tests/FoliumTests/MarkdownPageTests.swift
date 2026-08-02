import Testing
@testable import Folium

struct MarkdownPageTests {
    @Test func wrapsFragmentInFullDocument() {
        let page = MarkdownPage.html(bodyHTML: "<h1>Hi</h1>")

        #expect(page.hasPrefix("<!DOCTYPE html>"))
        #expect(page.contains("<html lang=\"en\">"))
        #expect(page.contains("<head>"))
        #expect(page.contains("</html>"))
    }

    @Test func embedsTheRenderedBody() {
        let page = MarkdownPage.html(bodyHTML: "<p>rendered content</p>")
        #expect(page.contains("<p>rendered content</p>"))
    }

    @Test func appliesTheGitHubStylesheet() {
        let page = MarkdownPage.html(bodyHTML: "")

        #expect(page.contains("<style>"))
        #expect(page.contains(GitHubStylesheet.css))
        // Body content is wrapped in the styled container.
        #expect(page.contains(#"class="markdown-body""#))
    }

    @Test func declaresSystemColorScheme() {
        let page = MarkdownPage.html(bodyHTML: "")
        // WKWebView needs this to report the system light/dark setting.
        #expect(page.contains(#"<meta name="color-scheme" content="light dark">"#))
    }

    @Test func stylesheetSupportsLightAndDarkMode() {
        // The light palette is the default; dark swaps in via prefers-color-scheme.
        #expect(GitHubStylesheet.css.contains("color-scheme: light dark;"))
        #expect(GitHubStylesheet.css.contains("@media (prefers-color-scheme: dark)"))
    }

    @Test func stylesheetCoversTheAcceptanceCriteriaElements() {
        let css = GitHubStylesheet.css
        // Headings, paragraphs, blockquotes, lists, tables, images, hr, links.
        #expect(css.contains(".markdown-body h1"))
        #expect(css.contains(".markdown-body p"))
        #expect(css.contains(".markdown-body blockquote"))
        #expect(css.contains(".markdown-body ul"))
        #expect(css.contains(".markdown-body ol"))
        #expect(css.contains(".markdown-body table"))
        #expect(css.contains(".markdown-body img"))
        #expect(css.contains(".markdown-body hr"))
        #expect(css.contains(".markdown-body a"))
    }
}
