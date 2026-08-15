---
status: accepted
---

# Tabs via SwiftUI `DocumentGroup`, not a custom tab strip

Multiple open files are presented as native macOS window tabs (the same tab
bar Safari/Finder/Xcode/Terminal use), implemented via a SwiftUI
`DocumentGroup` scene backed by a `FileDocument`/`ReferenceFileDocument`,
rather than a hand-built in-window tab strip.

"Feel native and slick" was set as an explicit bar for this app from the
outset, and tabs are a core, load-bearing requirement (not an incidental
feature) — so the standard OS widget users already have muscle memory for
(drag to reorder, drag out to a new window, `⌘T`/`⌘W`, Mission Control
integration) was judged a better fit than reimplementing that behavior.
`DocumentGroup` gets this, plus File > Open, Recent Documents, and window
restoration, largely for free on macOS.

## Considered options

- **Custom in-app tab strip** — rejected. Full control over visual treatment
  (e.g. unsaved-state dots, custom badges) and a simpler state model (an
  array of open documents + a selected index), but loses native drag/
  Mission Control behavior for free and risks reading as a web-app tab
  knockoff rather than a native Mac citizen — directly against the stated
  design goal.

## Consequences

- The document model is constrained to `FileDocument`/`ReferenceFileDocument`
  conformance, and "one window per document" is the assumed architecture
  going forward — any future feature (e.g. a sidebar showing multiple files
  in one window) would need to work within or deliberately break that
  assumption.
- **"Largely for free" was optimistic**, as building it out under issue #5
  showed. File > Open, Recent Documents, and *not* opening a second window for
  an already-open file are genuinely free. Two things are not:
  - **Tabbing.** `DocumentGroup` windows default to the system-wide "Prefer
    tabs when opening documents" setting, whose default is *In Full Screen
    Only* — so out of the box, opening three files gives three loose windows.
    Folium sets `tabbingMode`/`tabbingIdentifier` on each document window and
    calls `addTabbedWindow(_:ordered:)` itself. That is still AppKit's real tab
    group (drag-to-reorder, drag-out, ⌘W, Mission Control all come with it), so
    the "no custom tab strip" decision stands — it just has to be asked for.
  - **State restoration.** SwiftUI's built-in app delegate does not opt into
    secure restorable state, and AppKit persists nothing for an app that
    hasn't, so nothing reopened after a quit. Folium supplies its own
    `NSApplicationDelegate` for that.

  Both failures are silent — the app looks fine and simply doesn't do the
  thing — which is why they have integration tests rather than a manual note.
