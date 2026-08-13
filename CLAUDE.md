## What this project optimizes for

Read [`CONTEXT.md`](CONTEXT.md) before making changes. It records the product's
floors and its ordered priorities, so decisions an issue doesn't cover can
still be made the way the project would make them.

The short version — **floors** (never traded): the document says what the file
says; no network, ever; the gates pass. **Priorities** (higher wins collisions):
1. native Mac citizen → 2. perceived latency → 3. GitHub fidelity inside the
document → 4. scope restraint. Or, in one line: *the app grows toward
completeness on OS integration, and stays flat on invented features.*

## Definition of Done

Every code change must pass all quality gates before the work is done: lint,
vet, unit tests, integration tests, and **≥97% unit-test line coverage on the
logic layer**. Run `make check` (or the individual `make lint` / `make vet` /
`make test-unit` / `make test-integration` / `make coverage` recipes).

Keep real logic (parsing, rendering, decoding, business rules) in plain,
unit-testable types with no SwiftUI/AppKit/WebKit dependency — the UI/host-glue
files are excluded from the coverage requirement and must stay thin. See
`docs/agents/definition-of-done.md`.

For *how* to test — especially rendering/styling, where output is HTML+CSS
interpreted by WebKit — see `docs/agents/testing.md`. The rule of thumb: test the
seam this app owns (wiring, integration decisions), not the values our
dependencies (cmark-gfm, GitHub's CSS) already test.

## Agent skills

### Issue tracker

Issues live as GitHub issues in telday/markdown-viewer, managed via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
