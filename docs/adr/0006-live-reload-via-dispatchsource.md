---
status: accepted
---

# Live-reload watches each file with a `DispatchSource`, not `NSFilePresenter`

An open document watches its own backing file with a per-file
`DispatchSource.makeFileSystemObjectSource` over an `O_EVTONLY` descriptor
(`FileWatcher`). Notifications are collapsed into one reload per 50 ms window
(`ReloadCoalescer`), and the reload re-reads the path and re-renders
(`LiveDocument`).

Folium is permanently a viewer (`CONTEXT.md` non-goals), so live-reload is not
a convenience — it is the other half of the only workflow the app has: the user
edits in their real editor and reads here. That is why there is no manual
refresh command. There is nothing for one to do.

`CONTEXT.md`'s priority 1 says never to reimplement what AppKit provides, so
the first question was whether the document framework already does this. It
does not, for us: `DocumentGroup(viewing:)` reads the file once and hands the
content over as a value. AppKit's own "revert an unedited document when the
file changes" behavior lives on `NSDocument`, which a SwiftUI `FileDocument`
app never gets to see, let alone override — and `NSFilePresenter`, the
supported way to ask for those callbacks, has to be registered by an object
with a document's lifetime, which is exactly the object `DocumentGroup` does
not expose. This is the same shape as ADR 0004's "largely for free was
optimistic" finding: the affordance is standard, and we still have to build it.

## Considered options

- **`NSFilePresenter` / `NSFileCoordinator`** — the framework answer, and
  preferred if it were reachable. It needs a presenter object registered with
  the coordination system for as long as the document is open; SwiftUI's
  `DocumentGroup` owns that lifetime and hands out only a value type. It also
  buys coordination against *other* writers, which is worth real money to an
  editor and nothing at all to a viewer that never writes.
- **`FSEventStream` on the containing directory** — handles atomic saves
  without any re-open bookkeeping, because the watch is on the directory rather
  than the inode. Rejected: it reports at directory granularity with a latency
  floor measured in hundreds of milliseconds by default, against a 100 ms
  repaint budget, and watching a whole directory to learn about one file is a
  much larger permission and event surface than the document needs. For a repo
  checkout with a build running in it, most of what it reports is noise.
- **Polling `stat`** — rejected outright. It is either slow or it burns CPU in
  every open window forever, and the kernel already offers the answer.

## Consequences

- **Atomic saves have to be handled explicitly.** Most editors save by writing
  a temporary file and renaming it over the original, so the path ends up
  naming a new inode while the watch still holds the old one open. A rename or
  delete therefore means both "re-read" and "re-open the path", with a bounded
  retry for editors that unlink before writing. Get this wrong and live-reload
  works exactly once per document and then goes quiet — a silent failure, which
  is why `FileWatcherTests` asserts the *second* save, not just the first.
- **The 50 ms coalescing window is spent out of the 100 ms repaint budget.**
  Measured end to end against the built app, an external save repaints ~54 ms
  after the write, for both in-place and atomic saves. Widening the window
  spends budget that the read and the render also need.
- **One descriptor per open document**, released when the window closes.
- The watch is best-effort: a file that cannot be opened, or that stays gone
  past the retry budget, leaves the document on screen without live-reload
  rather than failing the open or blanking the window.
