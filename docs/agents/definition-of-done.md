# Definition of Done

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

## Rules

- **All four must pass.** A change is not done while any gate is red. Do not
  disable a rule or skip a gate to make it pass — fix the code, or if a rule is
  genuinely wrong for this repo, change the shared config (`.swiftlint.yml`,
  the `Makefile` recipe) deliberately and say so in the PR.
- **New behavior needs tests.** A change that adds or changes runtime behavior
  should extend the unit or integration suite accordingly; the gate passing on
  unchanged tests is not sufficient coverage for new logic.
- **`swiftlint` is required tooling.** Install it with `brew install swiftlint`.
  `make lint` fails with an install hint if it is missing.
