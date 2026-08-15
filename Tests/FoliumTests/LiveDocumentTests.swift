import Combine
import Foundation
import Testing
@testable import Folium

/// The re-read-and-re-render half of live-reload (issue #7).
///
/// The coalescing window is driven by hand here so the assertions are about
/// *what* gets rendered rather than about when a sleep finished;
/// `LiveReloadTests` in the integration target runs the same path on the real
/// clock.
@MainActor
struct LiveDocumentTests {
    @Test func rendersTheContentItWasOpenedWith() throws {
        let file = try TempFile(contents: "# Opened")
        let scheduler = ManualScheduler()

        let document = LiveDocument(text: "# Opened", fileURL: file.url, scheduler: scheduler)

        #expect(document.bodyHTML.contains("<h1>Opened</h1>"))
    }

    @Test func picksUpAnExternalEditWithoutBeingAskedTo() throws {
        let file = try TempFile(contents: "# Opened")
        let scheduler = ManualScheduler()
        let document = LiveDocument(text: "# Opened", fileURL: file.url, scheduler: scheduler)

        try file.write("# Edited elsewhere")
        document.fileDidChange()
        scheduler.elapse()

        #expect(document.bodyHTML.contains("<h1>Edited elsewhere</h1>"))
        #expect(!document.bodyHTML.contains("Opened"))
    }

    @Test func rendersTheFileRatherThanWhateverTheNotificationClaimed() throws {
        // The floor in CONTEXT.md: the document says what the file says. The
        // notification carries no content, so the only source of truth is a
        // fresh read of the path.
        let file = try TempFile(contents: "# Opened")
        let scheduler = ManualScheduler()
        let document = LiveDocument(text: "# Stale in-memory copy", fileURL: file.url, scheduler: scheduler)

        document.fileDidChange()
        scheduler.elapse()

        #expect(document.bodyHTML.contains("<h1>Opened</h1>"))
    }

    @Test func keepsTheLastGoodDocumentWhenTheFileIsMidSave() throws {
        // A save is briefly a missing path; blanking the window on the way past
        // would be worse than content that is milliseconds stale.
        let file = try TempFile(contents: "# Opened")
        let scheduler = ManualScheduler()
        let document = LiveDocument(text: "# Opened", fileURL: file.url, scheduler: scheduler)

        try file.remove()
        document.fileDidChange()
        scheduler.elapse()

        #expect(document.bodyHTML.contains("<h1>Opened</h1>"))
    }

    @Test func keepsTheLastGoodDocumentWhenTheBytesDoNotDecode() throws {
        let file = try TempFile(contents: "# Opened")
        let scheduler = ManualScheduler()
        let document = LiveDocument(text: "# Opened", fileURL: file.url, scheduler: scheduler)

        // A half-written UTF-8 sequence — what a reader can catch an editor
        // mid-write with.
        try file.writeBytes(Data([0xFF, 0xFE, 0xFD]))
        document.fileDidChange()
        scheduler.elapse()

        #expect(document.bodyHTML.contains("<h1>Opened</h1>"))
    }

    @Test func aChangeThatRendersIdenticallyCostsNoRepaint() throws {
        // `touch`, a chmod, or a save of unchanged bytes. Publishing anyway
        // would push an injection into the web view for nothing, against
        // CONTEXT.md's second priority.
        let file = try TempFile(contents: "# Opened")
        let scheduler = ManualScheduler()
        let document = LiveDocument(text: "# Opened", fileURL: file.url, scheduler: scheduler)
        let publishes = Counter()
        let subscription = document.$bodyHTML.dropFirst().sink { _ in publishes.increment() }
        defer { subscription.cancel() }

        try file.write("# Opened")
        document.fileDidChange()
        scheduler.elapse()

        #expect(publishes.total == 0)

        // ...and the guard doesn't wedge it: a real edit still publishes.
        try file.write("# Really edited")
        document.fileDidChange()
        scheduler.elapse()

        #expect(publishes.total == 1)
    }

    @Test func aDocumentWithNoFileOnDiskSimplyHasNoLiveReload() {
        // `DocumentGroup` can hand over a document with no URL; it should
        // render and then sit there, not crash and not watch anything.
        let document = LiveDocument(text: "# Untitled", fileURL: nil)

        document.fileDidChange()

        #expect(document.bodyHTML.contains("<h1>Untitled</h1>"))
    }

    @Test func aDocumentWhoseFileCannotBeWatchedStillRenders() {
        // Live-reload is an enhancement to a document that is already on
        // screen. Failing to watch must not fail the open.
        let missing = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).md")

        let document = LiveDocument(text: "# Opened", fileURL: missing)

        #expect(document.bodyHTML.contains("<h1>Opened</h1>"))
    }
}

/// A clock the test advances; `elapse()` is the coalescing window closing.
@MainActor
private final class ManualScheduler: ReloadScheduler {
    private var pending: [@MainActor () -> Void] = []

    func schedule(after delay: Duration, run body: @escaping @MainActor () -> Void) {
        pending.append(body)
    }

    func elapse() {
        let due = pending
        pending = []
        for body in due { body() }
    }
}

@MainActor
private final class Counter {
    private(set) var total = 0

    func increment() {
        total += 1
    }
}

/// A Markdown file in its own temporary directory, deleted when the test's
/// reference to it goes away.
private final class TempFile {
    let url: URL
    private let directory: URL

    init(contents: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoliumTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("document.md")
        try write(contents)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func write(_ contents: String) throws {
        try writeBytes(Data(contents.utf8))
    }

    func writeBytes(_ data: Data) throws {
        try data.write(to: url)
    }

    func remove() throws {
        try FileManager.default.removeItem(at: url)
    }
}
