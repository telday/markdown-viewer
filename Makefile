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
	printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	codesign --force --sign - --identifier "$(BUNDLE_ID)" "$(APP_BUNDLE)"
	# SPM's generated Bundle.module accessor looks for the resource bundle as
	# a sibling of the .app itself (Bundle.main.bundleURL), not inside
	# Contents/Resources — its other fallback is a dev-machine-only absolute
	# .build path, so skipping this silently produces an app that only
	# happens to work on the machine it was built on and fatalErrors/crashes
	# on launch anywhere else. Copied in *after* signing: codesign refuses to
	# seal a bundle with anything outside Contents/ at its root ("unsealed
	# contents present in the bundle root"), confirmed by testing both
	# orders. Signing first and adding this after still launches correctly
	# (verified by hiding the fallback .build path entirely and confirming
	# the app still finds its resources); `codesign --verify` will flag the
	# added directory as unsealed, which only matters if this ever moves
	# beyond ad-hoc signing (see ADR 0003).
	cp -R "$(BUILD_DIR)/$(APP_NAME)_$(APP_NAME).bundle" "$(APP_BUNDLE)/$(APP_NAME)_$(APP_NAME).bundle"
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
