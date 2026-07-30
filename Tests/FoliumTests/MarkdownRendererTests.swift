import Testing
@testable import Folium

struct MarkdownRendererTests {
    @Test func heading() {
        let html = MarkdownRenderer.renderHTML(from: "# Hello")
        #expect(html.contains("<h1>Hello</h1>"))
    }

    @Test func paragraph() {
        let html = MarkdownRenderer.renderHTML(from: "Just a paragraph.")
        #expect(html.contains("<p>Just a paragraph.</p>"))
    }

    @Test func table() {
        let markdown = """
        | A | B |
        | - | - |
        | 1 | 2 |
        """
        let html = MarkdownRenderer.renderHTML(from: markdown)
        #expect(html.contains("<table>"))
        #expect(html.contains("<th>A</th>"))
        #expect(html.contains("<td>1</td>"))
    }

    @Test func taskListCheckboxes() {
        let markdown = """
        - [ ] todo
        - [x] done
        """
        let html = MarkdownRenderer.renderHTML(from: markdown)
        #expect(html.contains(#"<input type="checkbox" disabled="" />"#))
        #expect(html.contains(#"<input type="checkbox" checked="" disabled="" />"#))
    }

    @Test func strikethrough() {
        let html = MarkdownRenderer.renderHTML(from: "~~gone~~")
        #expect(html.contains("<del>gone</del>"))
    }

    @Test func autolink() {
        let html = MarkdownRenderer.renderHTML(from: "See https://example.com for more.")
        #expect(html.contains(#"<a href="https://example.com">https://example.com</a>"#))
    }
}
