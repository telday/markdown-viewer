## Definition of Done

Every code change must pass all quality gates before the work is done: lint,
vet, unit tests, integration tests, and **≥97% unit-test line coverage on the
logic layer**. Run `make check` (or the individual `make lint` / `make vet` /
`make test-unit` / `make test-integration` / `make coverage` recipes).

Keep real logic (parsing, rendering, decoding, business rules) in plain,
unit-testable types with no SwiftUI/AppKit/WebKit dependency — the UI/host-glue
files are excluded from the coverage requirement and must stay thin. See
`docs/agents/definition-of-done.md`.

## Agent skills

### Issue tracker

Issues live as GitHub issues in telday/markdown-viewer, managed via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
