# Folium build & install.
#
# `make install` builds a release binary, assembles a Folium.app bundle,
# ad-hoc signs it, and copies it to /Applications. See ADR 0002 (SPM build)
# and ADR 0003 (unsandboxed, direct distribution).

APP_NAME    := Folium
BUNDLE_ID   := com.telday.Folium
CONFIG      := release
# Universal, so one bundle runs natively on Apple Silicon and on Intel rather
# than under Rosetta on one of them. Asking for a second architecture hands
# the build to Xcode's build system, which needs Xcode itself installed and
# selected — the Command Line Tools alone do not carry it (see ADR 0002's
# 2026-08-16 amendment).
ARCH_FLAGS  := --arch arm64 --arch x86_64
# Ask the Swift Package Manager where the products landed instead of
# hardcoding it. Xcode's build system puts them somewhere else entirely
# (.build/apple/Products/Release, against .build/arm64-apple-macosx/release),
# so the path follows the flags above. Deferred (`=`, not `:=`) so only the
# recipes that use it pay for the extra swift invocation.
BUILD_DIR    = $(or $(shell swift build -c $(CONFIG) $(ARCH_FLAGS) --show-bin-path), \
                    $(error could not read the products directory from swift build))
# Assemble the bundle under .build/ so the build artifact isn't left in the
# project directory, where Spotlight would index it as a second Folium app.
APP_BUNDLE  := .build/$(APP_NAME).app
CONTENTS    := $(APP_BUNDLE)/Contents
SOURCE_DIR  := Sources/$(APP_NAME)
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

## Compile the release binary, universal for both Mac architectures.
build: vendor
	swift build -c $(CONFIG) $(ARCH_FLAGS)

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
	# resolves against. Taken from the source tree, not from the resource
	# bundle the Swift Package Manager generates, so the .app doesn't inherit
	# that bundle's name and layout. See ADR 0003's 2026-08-16 amendment.
	cp -R "$(SOURCE_DIR)/Resources" "$(CONTENTS)/Resources/Resources"
	cp -R "$(SOURCE_DIR)/Vendor/HighlightJS" "$(CONTENTS)/Resources/HighlightJS"
	# Signing comes last: a signature seals the files present when it runs.
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
