## Definition of Done

Every code change must pass all four quality gates — lint, vet, unit tests, and
integration tests — before the work is done. Run `make check` (or the
individual `make lint` / `make vet` / `make test-unit` / `make test-integration`
recipes). See `docs/agents/definition-of-done.md`.

## Agent skills

### Issue tracker

Issues live as GitHub issues in telday/markdown-viewer, managed via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
