# Folium build & install.
#
# `make install` builds a release binary, assembles a Folium.app bundle,
# ad-hoc signs it, and copies it to /Applications. See ADR 0002 (SPM build)
# and ADR 0003 (unsandboxed, direct distribution).

APP_NAME    := Folium
BUNDLE_ID   := com.telday.Folium
CONFIG      := release
BUILD_DIR   := .build/$(CONFIG)
# Assemble the bundle under .build/ so the build artifact isn't left in the
# project directory, where Spotlight would index it as a second Folium app.
APP_BUNDLE  := .build/$(APP_NAME).app
CONTENTS    := $(APP_BUNDLE)/Contents
# The first-party and vendored assets, taken from the source tree — see the
# copy step in `bundle`.
RESOURCE_SRC := Sources/$(APP_NAME)
INSTALL_DIR := /Applications
INSTALLED   := $(INSTALL_DIR)/$(APP_NAME).app

.PHONY: all build bundle install uninstall clean vendor \
        check lint vet test test-unit test-integration coverage

all: bundle

## Run every Definition-of-Done gate: lint, vet, unit + integration tests, coverage.
## See docs/agents/definition-of-done.md.
check: lint vet test-unit test-integration coverage
	@echo "All quality gates passed."

## Style/convention linting (fails on any violation).
lint:
	@command -v swiftlint >/dev/null 2>&1 || { \
		echo "swiftlint not found. Install it with: brew install swiftlint"; exit 1; }
	swiftlint lint --strict

## Static analysis: compile all targets with warnings treated as errors
## (the closest Swift equivalent of `go vet`).
vet: vendor
	swift build --build-tests -Xswiftc -warnings-as-errors

## Run both test suites.
test: test-unit test-integration

## Fast, isolated unit tests.
test-unit: vendor
	swift test --filter FoliumTests

## Integration tests that exercise the file-to-render pipeline end to end.
test-integration: vendor
	swift test --filter FoliumIntegrationTests

## Enforce >=97% unit-test line coverage on the logic layer. Prints the
## excluded UI/host-glue files on every run. See scripts/coverage.sh.
coverage: vendor
	./scripts/coverage.sh

## Regenerate vendored third-party JS/CSS (Sources/Folium/Vendor/, gitignored)
## from vendor/package.json's pinned versions. A no-op once already current,
## so this is cheap to list as a prerequisite everywhere `swift build`/`swift
## test` runs. A bare `swift build` (bypassing make) needs this run first.
## See scripts/vendor-highlightjs.sh.
vendor:
	./scripts/vendor-highlightjs.sh

## Compile the release binary.
build: vendor
	swift build -c $(CONFIG)

## Assemble and ad-hoc sign $(APP_BUNDLE) from the release binary.
bundle: build
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(CONTENTS)/MacOS/$(APP_NAME)"
	cp packaging/Info.plist "$(CONTENTS)/Info.plist"
	# The Finder/Dock icon. `.icns` is a multi-resolution container, and
	# iconutil is the only supported way to produce one — it packs the ten
	# PNGs whose names encode the sizes macOS asks for (16pt through 512pt,
	# each @1x and @2x). Built here rather than committed so the PNGs stay
	# the reviewable source of truth.
	iconutil --convert icns --output "$(CONTENTS)/Resources/$(APP_NAME).icns" \
		packaging/$(APP_NAME).iconset
	printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	# The page shell and its CSS/JS, at the paths MarkdownPage.resourceBaseURL
	# resolves against: the same layout SPM's generated resource bundle has,
	# rooted at Contents/Resources instead. Copied from the source tree rather
	# than from that generated bundle, so the .app doesn't inherit whichever
	# name and layout the SPM build system in use happens to produce.
	cp -R "$(RESOURCE_SRC)/Resources" "$(CONTENTS)/Resources/Resources"
	cp -R "$(RESOURCE_SRC)/Vendor/HighlightJS" "$(CONTENTS)/Resources/HighlightJS"
	# Last: codesign seals what is in the bundle at signing time, and refuses
	# to sign at all if anything sits outside Contents/ at the bundle root
	# ("unsealed contents present in the bundle root").
	codesign --force --sign - --identifier "$(BUNDLE_ID)" "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"

## Install the bundle to /Applications.
install: bundle
	rm -rf "$(INSTALLED)"
	cp -R "$(APP_BUNDLE)" "$(INSTALLED)"
	@echo "Installed $(INSTALLED)"

## Remove the installed bundle from /Applications.
uninstall:
	rm -rf "$(INSTALLED)"

## Remove build artifacts and the local bundle.
clean:
	swift package clean
	rm -rf "$(APP_BUNDLE)"
