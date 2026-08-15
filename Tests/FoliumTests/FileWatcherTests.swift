import Foundation
import Testing
@testable import Folium

/// The kernel-level half of live-reload (issue #7), against real files.
///
/// These are unit tests rather than integration tests because `FileWatcher` has
/// no SwiftUI/AppKit/WebKit dependency and so is not on the coverage exclusion
/// list — and because the failure this guards against is quiet by nature: a
/// watch that survives exactly one save and then never fires again looks
/// identical to a file nobody edited.
struct FileWatcherTests {
    @Test func reportsAWriteToTheWatchedFile() async throws {
        let file = try TempFile(contents: "before")
        let changes = Counter()
        let watcher = FileWatcher(url: file.url, onChange: changes.increment)
        defer { watcher.cancel() }

        #expect(watcher.start())
        try file.write("after")

        #expect(await changes.reach(1))
    }

    @Test func keepsWatchingAcrossAnAtomicSave() async throws {
        // How most editors save: write a temporary file, rename it over the
        // original. The descriptor the watch holds is left pointing at an
        // inode that is no longer the document, so without the re-open this
        // reports the first save and nothing after it.
        let file = try TempFile(contents: "one")
        let changes = Counter()
        let watcher = FileWatcher(url: file.url, onChange: changes.increment)
        defer { watcher.cancel() }
        #expect(watcher.start())

        try file.atomicallyReplace(with: "two")
        #expect(await changes.reach(1))

        try file.atomicallyReplace(with: "three")
        #expect(await changes.reach(2))
    }

    @Test func recoversWhenTheFileIsRecreatedWithinTheRetryBudget() async throws {
        // Editors that unlink before writing (and a plain `rm` followed by a
        // fresh write) leave a gap where the path does not exist at all.
        let file = try TempFile(contents: "one")
        let changes = Counter()
        let watcher = FileWatcher(
            url: file.url,
            reopenRetryDelay: .milliseconds(30),
            onChange: changes.increment
        )
        defer { watcher.cancel() }
        #expect(watcher.start())

        try file.remove()
        #expect(await changes.reach(1))
        let afterDelete = changes.total

        // Long enough that the first re-open attempts have already failed
        // against a path that wasn't there.
        try await Task.sleep(for: .milliseconds(80))
        try file.write("two")
        // ...and long enough for a later attempt to find the new file.
        try await Task.sleep(for: .milliseconds(150))
        try file.write("three")

        #expect(await changes.reach(afterDelete + 1))
    }

    @Test func givesUpOnAFileThatStaysGone() async throws {
        let file = try TempFile(contents: "one")
        let changes = Counter()
        let watcher = FileWatcher(url: file.url, reopenAttempts: 0, onChange: changes.increment)
        defer { watcher.cancel() }
        #expect(watcher.start())

        try file.remove()
        #expect(await changes.reach(1))
        let afterDelete = changes.total

        try await Task.sleep(for: .milliseconds(100))
        try file.write("two")
        try await Task.sleep(for: .milliseconds(200))

        #expect(changes.total == afterDelete)
    }

    @Test func startingOnAMissingFileReportsFailureInsteadOfWatchingNothing() {
        let watcher = FileWatcher(url: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).md")) {}
        defer { watcher.cancel() }

        // The caller's cue that the document is on screen without live-reload,
        // rather than a silent no-op that looks like a watch.
        #expect(watcher.start() == false)
    }

    @Test func startingAfterCancellingDoesNotResurrectTheWatch() async throws {
        let file = try TempFile(contents: "one")
        let changes = Counter()
        let watcher = FileWatcher(url: file.url, onChange: changes.increment)

        watcher.cancel()

        #expect(watcher.start() == false)
        try file.write("two")
        try await Task.sleep(for: .milliseconds(200))
        #expect(changes.total == 0)
    }

    @Test func cancellingStopsNotifications() async throws {
        let file = try TempFile(contents: "one")
        let changes = Counter()
        let watcher = FileWatcher(url: file.url, onChange: changes.increment)
        #expect(watcher.start())

        try file.write("two")
        #expect(await changes.reach(1))
        let beforeCancel = changes.total

        watcher.cancel()
        try file.write("three")
        try await Task.sleep(for: .milliseconds(200))

        #expect(changes.total == beforeCancel)
    }

    @Test func aWatchStopsWhenItsWatcherIsReleased() async throws {
        // A closed document window must not leave a descriptor and a dispatch
        // source behind; deallocation is the only cancellation the app itself
        // performs.
        let file = try TempFile(contents: "one")
        let changes = Counter()
        do {
            let watcher = FileWatcher(url: file.url, onChange: changes.increment)
            #expect(watcher.start())
        }

        try file.write("two")
        try await Task.sleep(for: .milliseconds(200))

        #expect(changes.total == 0)
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
        try Data(contents.utf8).write(to: url)
    }

    func remove() throws {
        try FileManager.default.removeItem(at: url)
    }

    /// Saves the way an editor does: a temporary file renamed over the
    /// original.
    func atomicallyReplace(with contents: String) throws {
        let staging = directory.appendingPathComponent("staging-\(UUID().uuidString)")
        try Data(contents.utf8).write(to: staging)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: staging)
    }
}

/// Counts notifications, which arrive on the watcher's private queue.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var total: Int {
        lock.withLock { value }
    }

    @Sendable
    func increment() {
        lock.withLock { value += 1 }
    }

    /// Waits for the count to reach `target`, polling rather than parking on a
    /// continuation so a notification that arrives early can't be missed.
    /// The timeout is deliberately generous: it exists to fail a broken watch,
    /// not to measure one.
    func reach(_ target: Int, within timeout: Duration = .seconds(5)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if total >= target { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return total >= target
    }
}
