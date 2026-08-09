import Foundation
import Testing
@testable import Folium

/// Integration coverage for the file-to-HTML path the app runs on every open:
/// read a real Markdown file off disk, decode it as UTF-8 the way
/// `MarkdownDocument` does, and render it exactly as `FoliumApp` does. Unlike
/// the unit tests, this exercises the whole GFM feature set together against a
/// real fixture rather than one construct at a time.
struct RenderPipelineTests {
    private func renderFixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "md", subdirectory: "Fixtures"),
            "fixture \(name).md not found in test bundle"
        )
        let data = try Data(contentsOf: url)
        let markdown = try #require(String(data: data, encoding: .utf8))
        return MarkdownRenderer.renderHTML(from: markdown)
    }

    @Test func rendersEveryGFMFeatureFromFixture() throws {
        let html = try renderFixture("sample")

        // Core structure
        #expect(html.contains("<h1>Folium Sample</h1>"))
        #expect(html.contains("<h2>Checklist</h2>"))
        // Inline link and strikethrough
        #expect(html.contains(#"<a href="https://example.com">link</a>"#))
        #expect(html.contains("<del>struck</del>"))
        // Task list
        #expect(html.contains(#"<input type="checkbox" disabled="" />"#))
        #expect(html.contains(#"<input type="checkbox" checked="" disabled="" />"#))
        // Table
        #expect(html.contains("<table>"))
        #expect(html.contains("<th>Feature</th>"))
        #expect(html.contains("<td>tables</td>"))
        // Autolink
        #expect(html.contains(#"<a href="https://folium.example">https://folium.example</a>"#))
    }

    @Test func stylesTheRenderedDocumentEndToEnd() throws {
        // Exercises the exact composition `FoliumApp` performs on open: render
        // the fixture, then build the injection script `MarkdownWebView` sends
        // into its already-loaded, GitHub-styled shell.
        let bodyHTML = try renderFixture("sample")
        let script = MarkdownPage.renderBodyScript(bodyHTML: bodyHTML)

        // The rendered content survives decoration and JSON-escaping ("/" comes
        // through escaped as "\/" in closing tags — see MarkdownPageTests)...
        #expect(script.contains(#"<h1>Folium Sample<\/h1>"#))
        #expect(script.contains("<table>"))
        // ...wrapped in the call that injects it into the shell's container.
        #expect(script.hasPrefix(#"window.FoliumRenderBody(""#))
    }
}
