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

.PHONY: all build bundle install uninstall clean

all: bundle

## Compile the release binary.
build:
	swift build -c $(CONFIG)

## Assemble and ad-hoc sign $(APP_BUNDLE) from the release binary.
bundle: build
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(CONTENTS)/MacOS/$(APP_NAME)"
	cp packaging/Info.plist "$(CONTENTS)/Info.plist"
	printf 'APPL????' > "$(CONTENTS)/PkgInfo"
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
