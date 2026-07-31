import cmark_gfm
import cmark_gfm_extensions

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Converts Markdown to HTML via cmark-gfm, with the table, strikethrough,
/// tasklist, and autolink GFM extensions attached (ADR 0005). This is the
/// only place in the app that touches the cmark-gfm C API.
enum MarkdownRenderer {
    private static let extensionNames = ["table", "strikethrough", "tasklist", "autolink"]

    static func renderHTML(from markdown: String) -> String {
        cmark_gfm_core_extensions_ensure_registered()

        // The cmark C calls below only return nil on allocation failure, which
        // isn't reachable from any Markdown input; the guards stay on one line
        // so line coverage isn't dragged down by branches tests can't hit.
        guard let parser = cmark_parser_new(CMARK_OPT_DEFAULT) else { return "" }
        defer { cmark_parser_free(parser) }

        for name in extensionNames {
            if let syntaxExtension = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, syntaxExtension)
            }
        }

        markdown.withCString { cString in
            cmark_parser_feed(parser, cString, strlen(cString))
        }

        guard let document = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(document) }

        let attachedExtensions = cmark_parser_get_syntax_extensions(parser)
        guard let htmlCString = cmark_render_html(document, CMARK_OPT_DEFAULT, attachedExtensions) else { return "" }
        defer { free(htmlCString) }

        return String(cString: htmlCString)
    }
}
