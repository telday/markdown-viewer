# Definition of Done

> This doc defines *which gates must pass*. For *how to test* — the tiers of
> rendering tests, what's worth asserting vs. what's a dependency's job, and
> where each kind of test lives — see [testing.md](testing.md).

Every code change made by an agent must pass all four quality gates before it
is considered done (before opening or updating a PR, and before claiming the
work is complete). Run them all with:

```sh
make check
```

or individually:

| Gate | Command | What it checks |
| ---- | ------- | -------------- |
| Lint | `make lint` | Style and convention via SwiftLint (`--strict`; any violation fails). Config in `.swiftlint.yml`. |
| Vet | `make vet` | Static analysis — compiles all targets (including tests) with warnings treated as errors. The Swift equivalent of `go vet`; Swift folds these checks into the compiler. |
| Unit tests | `make test-unit` | Fast, isolated tests (`FoliumTests` target). |
| Integration tests | `make test-integration` | End-to-end pipeline tests (`FoliumIntegrationTests` target), e.g. reading a real Markdown file off disk and rendering it. |
| Coverage | `make coverage` | **≥97% unit-test line coverage on the logic layer.** See below. |

## Unit-test coverage (≥97% on the logic layer)

`make coverage` measures **line** coverage from the unit tests (`FoliumTests`
only) and fails if the logic layer is below 97%.

It cannot be 97% across the *whole* app: SwiftUI/AppKit/WebKit host glue only
runs when the app or the document framework is live, so unit tests can't reach
it. Those files are therefore **excluded** from the requirement. The exclusion
list lives in one place — `scripts/coverage.sh` — and is **printed on every
run** so it's always visible. Currently excluded:

- `Sources/Folium/FoliumApp.swift` — the `@main` `App`/`Scene`, only runs on launch.
- `Sources/Folium/MarkdownWebView.swift` — `NSViewRepresentable` over `WKWebView`.
- `Sources/Folium/MarkdownDocument.swift` — `FileDocument` conformance; only the
  SwiftUI document machinery constructs its `ReadConfiguration`.
- `Sources/Folium/DocumentWindowTabber.swift` — `NSViewRepresentable` plus
  `NSWindow` tab-group calls; needs live windows.
- `Sources/Folium/FoliumAppDelegate.swift` — `NSApplicationDelegate`; only AppKit
  calls it, at launch.

### Keep logic in unit-testable units

Because the excluded files are exempt from coverage, they must stay **thin
glue**. Put real logic — parsing, rendering, decoding, formatting, any
branching business rules — in plain types/functions with **no SwiftUI / AppKit /
WebKit dependency**, so it lives in a covered file and the unit tests can reach
it. Example: file bytes are decoded in `MarkdownLoading` (testable), not inside
`MarkdownDocument.init(configuration:)` (glue). Growing the logic inside an
excluded file to dodge the coverage bar is not allowed; extract it instead.

Adding a file to the exclusion list is a deliberate change to
`scripts/coverage.sh` — do it only for genuinely unreachable host glue, and call
it out in the PR.

### The gate is a floor, not a target

97% is the line the build must not fall below. It is not a score to maximise,
and the last few lines are not worth deforming the code to reach.

A handful of lines that only run inside a real `.app` — a `Bundle.main` lookup,
an `NSWorkspace` call — can sit in a covered file and go unexecuted by the unit
tests. That is fine while the gate holds. What is not fine is inverting a
readable piece of code into injected closures and stub parameters so that a
test can drive it, when the test then exercises the stub rather than the
platform. Check the actual number before assuming the gate forces your hand:
this rule exists because issue #34 was specified around a coverage constraint
that turned out to cost 0.27 points.

Where the untested lines are a real risk, the honest guard is usually a level
up — an integration test, or a check against the assembled bundle — not a unit
test with the platform stubbed out.

### Exclusion obliges integration coverage

**"Excluded from unit coverage" must never come to mean "untested."** Any file
on the exclusion list must have its behavior asserted in
`FoliumIntegrationTests`, using the tier-2 computed-style / real-engine pattern
in [testing.md](testing.md).

This matters more as the app grows. `CONTEXT.md`'s priority 1 (native Mac
citizen) commits the project to a steady stream of AppKit↔WebKit bridging —
Find, print, Services, navigation policy, VoiceOver, state restoration — all of
which lands in excluded glue. Without this rule, `make coverage` keeps
reporting a green 97% over a shrinking fraction of the codebase while the
riskiest seam in the app is measured by nothing.

Concretely: the navigation-policy handler needs an integration test proving an
external link does not navigate the web view, and the Content-Security-Policy
needs one proving a remote image fails to load.

`make coverage` also reports the excluded files' line count and share of the
codebase on every run, so this erosion stays visible rather than silent.

## Rules

- **All gates must pass.** A change is not done while any gate is red. Do not
  disable a rule or skip a gate to make it pass — fix the code, or if a rule is
  genuinely wrong for this repo, change the shared config (`.swiftlint.yml`,
  `scripts/coverage.sh`, the `Makefile` recipe) deliberately and say so in the PR.
- **New behavior needs tests.** A change that adds or changes runtime behavior
  should extend the unit or integration suite accordingly; the gate passing on
  unchanged tests is not sufficient coverage for new logic.
- **`swiftlint` is required tooling.** Install it with `brew install swiftlint`.
  `make lint` fails with an install hint if it is missing.
