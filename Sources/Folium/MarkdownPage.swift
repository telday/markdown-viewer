/// Wraps a rendered Markdown HTML fragment (the output of `MarkdownRenderer`) in
/// a complete HTML document with the GitHub base stylesheet applied, so the page
/// WKWebView loads visually matches GitHub's Markdown rendering (issue #3), with
/// syntax-highlighted, copyable code blocks (issue #4).
///
/// This is plain string assembly with no WebKit/AppKit dependency, so it lives
/// in the unit-testable logic layer rather than in `MarkdownWebView` glue. The
/// `color-scheme` meta tag lets WKWebView report the system light/dark setting
/// to the stylesheet's `prefers-color-scheme` query.
enum MarkdownPage {
    /// Builds the full HTML document that hosts the given rendered body fragment.
    static func html(bodyHTML: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <style>
        \(GitHubStylesheet.css)
        \(HighlightJSTheme.css)
        \(CodeBlockStylesheet.css)
        </style>
        </head>
        <body>
        <article class="markdown-body">
        \(CodeBlockDecorator.decorate(bodyHTML))
        </article>
        <script>
        \(HighlightJS.script)
        </script>
        <script>
        \(CodeBlockScript.script)
        </script>
        </body>
        </html>
        """
    }
}
