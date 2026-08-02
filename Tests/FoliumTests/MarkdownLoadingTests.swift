import Foundation
import Testing
@testable import Folium

struct MarkdownLoadingTests {
    @Test func decodesUTF8() throws {
        let data = Data("# Héllo 🌿".utf8)
        let text = try MarkdownLoading.text(fromUTF8: data)
        #expect(text == "# Héllo 🌿")
    }

    @Test func decodesEmptyData() throws {
        let text = try MarkdownLoading.text(fromUTF8: Data())
        #expect(text.isEmpty)
    }

    @Test func throwsOnInvalidUTF8() {
        // 0xC3 0x28 is an invalid UTF-8 sequence.
        let data = Data([0xC3, 0x28])
        #expect(throws: CocoaError.self) {
            try MarkdownLoading.text(fromUTF8: data)
        }
    }
}
