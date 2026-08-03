import Foundation

/// Wraps every fenced/indented code block cmark-gfm emits (`<pre><code
/// class="language-X">...</code></pre>`, or the same without the class for
/// unlabeled blocks) in the chrome `CodeBlockStylesheet` styles: a header bar
/// with the declared language and a Copy button, ready for `CodeBlockScript`
/// to wire up at runtime.
///
/// Plain string transformation with no WebKit dependency, so it lives in the
/// unit-testable logic layer alongside `MarkdownRenderer` and `MarkdownPage`.
/// Relies on cmark-gfm's HTML output being one regular, escaped shape (ADR
/// 0005) — this is our seam to test, not a general-purpose HTML parser.
enum CodeBlockDecorator {
    private static let codeBlockPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"<pre><code(?: class="language-([^"]+)")?>.*?</code></pre>"#,
            options: [.dotMatchesLineSeparators]
        )
    }()

    static func decorate(_ bodyHTML: String) -> String {
        let fullRange = NSRange(bodyHTML.startIndex..., in: bodyHTML)
        let matches = codeBlockPattern.matches(in: bodyHTML, range: fullRange)
        guard !matches.isEmpty else { return bodyHTML }

        var result = ""
        var lastEnd = bodyHTML.startIndex

        for match in matches {
            guard let matchRange = Range(match.range, in: bodyHTML) else { continue }
            result += bodyHTML[lastEnd..<matchRange.lowerBound]

            let language = Range(match.range(at: 1), in: bodyHTML).map { String(bodyHTML[$0]) }
            result += wrap(preCodeHTML: String(bodyHTML[matchRange]), language: language)

            lastEnd = matchRange.upperBound
        }
        result += bodyHTML[lastEnd...]

        return result
    }

    private static func wrap(preCodeHTML: String, language: String?) -> String {
        let languageLabel = language.map { #"<span class="code-block-lang">\#($0)</span>"# } ?? ""
        return """
        <div class="code-block">
        <div class="code-block-header">\(languageLabel)<button type="button" class="copy-button">Copy</button></div>
        \(preCodeHTML)
        </div>
        """
    }
}
