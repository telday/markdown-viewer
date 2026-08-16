# Comments

> This doc is about *comments*. For which gates must pass, see
> [definition-of-done.md](definition-of-done.md); for what to test and where,
> see [testing.md](testing.md).

## Who you are writing for

**An experienced software engineer who has never written a macOS app.**

Assume they know their craft. Concurrency, file descriptors, debouncing, retain
cycles, the shape of a test suite — none of that needs explaining.

Assume they know nothing about this platform. AppKit, SwiftUI, WebKit, Dispatch,
`NSDocument`, the responder chain, how a `.app` bundle is laid out. That gap is
what most comments here exist to close.

## Comment the surprise

The code already says what it does. A comment earns its place when the code is
correct for a reason the reader cannot see — and on this platform that is
usually a framework behaving in a way nobody would guess:

- *"Dispatch crashes if a source is released without ever being resumed"* —
  without it, `source.cancel(); source.resume()` reads as a mistake.
- *"`DocumentGroup` reads the file once and hands over a plain value"* — without
  it, `LiveDocument` reads as reinventing something the framework provides.
- *"most editors save by writing a temporary file and renaming it over the
  original"* — without it, the re-open logic reads as paranoia.

If you learned something by running the built app, write it down along with what
you actually observed. Those are the comments that save the next person from
re-deriving it.

## Say it plainly

A comment that has to be re-read has failed, however accurate it is. Four rules,
in the order they go wrong:

**Spell an abbreviation out the first time a file uses it.** "SPM" costs the
reader a search; "the Swift Package Manager (SPM)" costs four words. The same
goes for anything that reads as insider shorthand: the tool, the framework, the
build step — name it once in full.

**One idea per sentence.** Most unreadable comments here are one sentence
carrying three facts, held together by a dash, a colon, and a subordinate
clause. Split them. Two plain sentences beat one clever one.

**Cut words that carry nothing.** *actually, really, simply, just, merely,
quite, of course, note that, at all, in every case, it is worth noting.* They
survive from a first draft where the writer was persuading themselves. Delete
them and check the sentence still says the same thing — it will.

**Use ordinary verbs, not API names as verbs.** "Crashes" reads faster than
"`fatalError`s". Name the symbol when the reader needs to search for it, then
describe what it does in English.

```swift
// Before — one sentence, three facts, two qualifiers.
/// `fallback` is `@autoclosure` because reaching for a bundle can be fatal,
/// not merely empty: SPM's generated `Bundle.module` accessor `fatalError`s
/// when it can't find its resource bundle. Evaluating it eagerly would crash
/// an app that has its own resources and never needed the fallback at all.

// After.
/// `fallback` is `@autoclosure` so it is only evaluated if it is used.
/// The Swift Package Manager generates the `Bundle.module` accessor, and
/// that accessor crashes when its resource bundle is missing. An app
/// carrying its own resources never needs the fallback, and must not
/// crash reaching for it.
```

## What not to write

**Don't restate the repo's rules.** `scripts/coverage.sh` lists its own
exclusions and `CONTEXT.md` states the priorities. Repeating them in a file
header means they are now wrong in two places instead of one. One pointer beats
a paragraph.

**Don't argue for the code.** Explain it and stop. This came out of
`FileWatcher`, and nothing was lost:

```swift
// Before
/// Everything here is Dispatch and POSIX, with no SwiftUI/AppKit/WebKit
/// dependency, so it stays in the unit-tested logic layer rather than joining
/// the coverage-excluded glue: the failure mode this guards against — the
/// watch surviving exactly one save and then going quiet forever — is
/// precisely the kind that an untested file would ship with.

// After — deleted. The one fact worth keeping ("a watch that survives exactly
// one save looks like a file nobody edited") moved to the test that asserts it.
```

**Don't name-drop an API when a plain description is clearer.** "The kernel
pushes notifications to us (via a Dispatch file-system source on an open
descriptor)" tells the reader more than "a `DispatchSource` file-system source
over an `O_EVTONLY` descriptor". Use the exact symbol when the reader will need
to search for it; otherwise describe the behavior.

**Don't cross-reference by reflex.** Link when the reader genuinely has to go
there, not to show the thought connects to something.

## Length

A doc comment longer than the code it documents needs a reason. Usually the
reason is real — a genuinely surprising platform behavior — and then it is
fine. Sometimes it means the same point is being made three times.

## Comments that are already there

**Leave them alone.** This is how to write the comments *you* are writing. It is
not a license to reformat comments in code you are not otherwise changing —
that produces a diff nobody can review, mixed in with one they need to.
