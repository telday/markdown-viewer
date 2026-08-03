import Testing
@testable import Folium

struct CodeBlockDecoratorTests {
    @Test func wrapsALabeledCodeBlockInChrome() {
        let body = #"<pre><code class="language-swift">let x = 1\n</code></pre>"#
        let decorated = CodeBlockDecorator.decorate(body)

        #expect(decorated.contains(#"class="code-block""#))
        #expect(decorated.contains(#"class="code-block-header""#))
        #expect(decorated.contains(#"<span class="code-block-lang">swift</span>"#))
        #expect(decorated.contains(#"<button type="button" class="copy-button">Copy</button>"#))
        // The original pre/code markup survives untouched inside the wrapper,
        // so highlight.js still finds the language class it needs.
        #expect(decorated.contains(#"<pre><code class="language-swift">let x = 1\n</code></pre>"#))
    }

    @Test func omitsTheLanguageLabelForAnUnlabeledBlock() {
        let body = "<pre><code>plain text\n</code></pre>"
        let decorated = CodeBlockDecorator.decorate(body)

        #expect(decorated.contains(#"class="code-block""#))
        #expect(decorated.contains(#"<button type="button" class="copy-button">Copy</button>"#))
        #expect(!decorated.contains("code-block-lang"))
    }

    @Test func leavesInlineCodeUntouched() {
        let body = "<p>Use <code>let</code> to declare a constant.</p>"
        let decorated = CodeBlockDecorator.decorate(body)

        #expect(decorated == body)
    }

    @Test func leavesContentWithoutCodeBlocksUntouched() {
        let body = "<h1>Title</h1><p>Just prose.</p>"
        #expect(CodeBlockDecorator.decorate(body) == body)
    }

    @Test func wrapsEachBlockIndependentlyWhenThereAreSeveral() {
        let body = """
        <pre><code class="language-swift">one\n</code></pre>
        <p>between</p>
        <pre><code class="language-python">two\n</code></pre>
        """
        let decorated = CodeBlockDecorator.decorate(body)

        #expect(decorated.contains(#"<span class="code-block-lang">swift</span>"#))
        #expect(decorated.contains(#"<span class="code-block-lang">python</span>"#))
        #expect(decorated.contains("<p>between</p>"))
        // Two independent wrappers, not one that swallows everything in between.
        #expect(decorated.components(separatedBy: #"class="code-block""#).count - 1 == 2)
    }

    @Test func preservesSurroundingContentBeforeAndAfterTheBlock() {
        let body = #"<h2>Example</h2><pre><code class="language-go">fmt.Println()\n</code></pre><p>done</p>"#
        let decorated = CodeBlockDecorator.decorate(body)

        #expect(decorated.hasPrefix("<h2>Example</h2><div class=\"code-block\">"))
        #expect(decorated.hasSuffix("</div><p>done</p>"))
    }
}
