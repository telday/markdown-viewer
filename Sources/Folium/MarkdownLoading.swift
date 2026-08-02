import Foundation

/// Turns the raw bytes of a Markdown file into text. Kept separate from
/// `MarkdownDocument`'s `FileDocument` conformance (which can only run inside
/// SwiftUI's document machinery) so the decoding logic is plain, dependency-free,
/// and unit-testable.
enum MarkdownLoading {
    /// Decodes file contents as UTF-8.
    /// - Throws: `CocoaError(.fileReadCorruptFile)` if the bytes aren't valid UTF-8.
    static func text(fromUTF8 data: Data) throws -> String {
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return string
    }
}
