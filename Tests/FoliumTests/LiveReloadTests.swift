import Testing
@testable import Folium

/// The live-reload policy (issue #7). The interesting case is the atomic save:
/// most editors write to a temporary file and rename it over the original, so a
/// watch that only re-read on `write` would report the first save and then go
/// silent forever.
struct LiveReloadTests {
    @Test func anInPlaceWriteJustReloads() {
        #expect(LiveReload.reaction(to: .written) == LiveReload.Reaction(reloads: true, reopens: false))
    }

    @Test func anAppendJustReloads() {
        #expect(LiveReload.reaction(to: .extended) == LiveReload.Reaction(reloads: true, reopens: false))
    }

    @Test func aRenameReloadsAndReopens() {
        // An editor's atomic save: the path now names a different inode than
        // the one the watch is holding open.
        #expect(LiveReload.reaction(to: .renamed) == LiveReload.Reaction(reloads: true, reopens: true))
    }

    @Test func aDeleteReloadsAndReopens() {
        #expect(LiveReload.reaction(to: .deleted) == LiveReload.Reaction(reloads: true, reopens: true))
    }

    @Test func aRevokeReloadsAndReopens() {
        #expect(LiveReload.reaction(to: .revoked) == LiveReload.Reaction(reloads: true, reopens: true))
    }

    @Test func aNotificationCarryingSeveralFlagsStillReopens() {
        // The kernel coalesces flags, so a save often arrives as one
        // notification covering both the write and the rename.
        let reaction = LiveReload.reaction(to: [.written, .renamed])
        #expect(reaction == LiveReload.Reaction(reloads: true, reopens: true))
    }

    @Test func anEmptyNotificationDoesNothing() {
        #expect(LiveReload.reaction(to: []) == LiveReload.Reaction(reloads: false, reopens: false))
    }

    @Test func theCoalescingWindowLeavesRoomInTheRepaintBudget() {
        // CONTEXT.md budgets 100 ms from "file written" to "repainted", and the
        // window is spent out of it before the read or the render has started.
        // This is the assertion that notices if someone widens it casually.
        #expect(LiveReload.coalescingWindow < .milliseconds(100))
        #expect(LiveReload.coalescingWindow > .zero)
    }

    @Test func theReopenBudgetIsBoundedAndBriefEnoughToBeInvisible() {
        // A file that is really gone must not leave a retry timer running for
        // the life of the window, and a save that is only mid-flight has to be
        // caught well inside the time a user would notice.
        #expect(LiveReload.reopenAttempts > 0)
        #expect(LiveReload.reopenRetryDelay * LiveReload.reopenAttempts <= .seconds(1))
    }
}
