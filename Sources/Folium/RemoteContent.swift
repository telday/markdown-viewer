import Foundation

/// Detects whether rendered document HTML references content the strict CSP
/// (`Resources/page.html`) blocks, so `RemoteContentState` knows when to show
/// the "Load remote images" bar (issue #19).
///
/// Scans `src`, `srcset`, and `poster` attribute values for an `http:` or
/// `https:` scheme, or a protocol-relative `//host/…` reference (a scheme-less
/// URL that inherits the page's own scheme — `file:` here, so it would
/// resolve to a nonexistent local path and fail, but a document author
/// writing it clearly means "fetch this over the network", and the bar should
/// say so). `href` is deliberately not scanned: a link is not loaded content,
/// and #17's navigation policy already keeps it from reaching the network.
///
/// This is plain string scanning with no SwiftUI/AppKit/WebKit dependency, so
/// it lives in the unit-tested logic layer.
enum RemoteContent {
    /// The attributes that load content directly, as opposed to `href`,
    /// which only navigates.
    private static let loadingAttributes = ["src", "srcset", "poster"]

    /// One compiled pattern per loading attribute, built once rather than on
    /// every call. `isReferenced` runs on every render, including every live
    /// reload (issue #7), inside CONTEXT.md's <=100ms live-reload budget —
    /// compiling three `NSRegularExpression`s from scratch on every one of
    /// those was paid whether or not the document had anything to flag.
    ///
    /// Each pattern matches its attribute's value either quoted (single or
    /// double) or bare — `<img src=https://example.com/x.png>` is legal HTML
    /// with no quotes at all. An unquoted value ends at the next whitespace
    /// or `>`.
    private static let attributePatterns: [String: NSRegularExpression] = {
        Dictionary(uniqueKeysWithValues: loadingAttributes.map { attribute in
            // The `=` required immediately after the attribute name (modulo
            // whitespace) is what keeps `src=` from also matching inside
            // `srcset=`: both names start with the same three letters, but
            // only `srcset` has more letters before its own `=`, so the
            // literal `=` right after `src` never lines up there. `srcset`
            // is matched by its own entry in this dictionary instead.
            let pattern = "\\b\(attribute)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
            // Built from a fixed, known-good set of attribute names, never
            // from document content, so this always compiles.
            // swiftlint:disable:next force_try
            return (attribute, try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))
        })
    }()

    /// Whether `html` references content the CSP will block.
    ///
    /// This is a regex scan over raw HTML text, not a parse: it has no
    /// notion of "inside a `<code>` block" or "inside an `<!-- -->`
    /// comment", so an `http:`/`https:` URL sitting in either of those still
    /// trips it. That is a deliberate, conservative choice — the failure
    /// mode is an unnecessary "Load" bar on a document with nothing to load,
    /// not a document whose real remote content goes unannounced. Getting
    /// this wrong in the other direction would mean rendered content the CSP
    /// silently blocks with no visible affordance to unblock it, which is
    /// exactly the floor-1 ("fail visibly") violation issue #19 exists to
    /// avoid.
    static func isReferenced(in html: String) -> Bool {
        loadingAttributes.contains { attribute in
            attributeReferencesRemoteContent(attribute, in: html)
        }
    }

    private static func attributeReferencesRemoteContent(_ attribute: String, in html: String) -> Bool {
        guard let regex = attributePatterns[attribute] else { return false }
        let range = NSRange(html.startIndex..., in: html)
        // `enumerateMatches` with `stop` rather than `matches(in:)`, so a
        // badge-heavy README stops scanning at the first remote reference
        // instead of collecting every match in the document before
        // `isReferenced` even looks at one of them.
        var found = false
        regex.enumerateMatches(in: html, range: range) { match, _, stop in
            guard let match else { return }
            let matchedRemoteContent = [1, 2, 3].contains { groupIndex in
                guard let valueRange = Range(match.range(at: groupIndex), in: html) else { return false }
                return valueReferencesRemoteContent(String(html[valueRange]), isSrcset: attribute == "srcset")
            }
            if matchedRemoteContent {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    private static func valueReferencesRemoteContent(_ value: String, isSrcset: Bool) -> Bool {
        guard isSrcset else { return isRemoteURL(value) }
        // srcset holds a comma-separated list of "url descriptor" pairs
        // (e.g. "small.png 1x, https://example.com/big.png 2x"); each URL
        // is checked on its own.
        return value.split(separator: ",").contains { candidate in
            let url = candidate.trimmingCharacters(in: .whitespaces).split(separator: " ").first ?? ""
            return isRemoteURL(String(url))
        }
    }

    private static func isRemoteURL(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("//") { return true }
        let lowercased = trimmed.lowercased()
        return lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://")
    }
}
