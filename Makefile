APP_NAME    := Chrysalism
BUNDLE      := $(APP_NAME).app
BINARY      := .build/release/$(APP_NAME)
INSTALL_DIR := $(HOME)/Applications
RELEASE_ZIP := $(APP_NAME)-macOS.zip

# Default to ad-hoc signing (-) if SIGNING_IDENTITY is not set in the environment
SIGNING_IDENTITY ?= -

.PHONY: all build app icon run debug install release clean

all: app

build:
	swift build -c release

icon:
	@rm -rf /tmp/chrysalism.iconset
	@mkdir -p /tmp/chrysalism.iconset
	@swift Scripts/mkicon.swift /tmp/chrysalism.iconset
	@iconutil -c icns /tmp/chrysalism.iconset -o BuildResources/AppIcon.icns
	@rm -rf /tmp/chrysalism.iconset
	@echo "Icon regenerated at BuildResources/AppIcon.icns"

app: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	cp "$(BINARY)" "$(BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp Info.plist "$(BUNDLE)/Contents/Info.plist"
	cp BuildResources/AppIcon.icns "$(BUNDLE)/Contents/Resources/AppIcon.icns"
	# Sign with your developer identity, enable hardened runtime, and apply a timestamp
	codesign --force --options runtime --timestamp --sign "$(SIGNING_IDENTITY)" "$(BUNDLE)"

run: app
	open "$(BUNDLE)"

debug:
	swift build && ./.build/debug/$(APP_NAME)

install: app
	rm -rf "$(INSTALL_DIR)/$(BUNDLE)"
	cp -R "$(BUNDLE)" "$(INSTALL_DIR)/"

# Release artifact for the GitHub release page: a zipped, signed app bundle
release: app
	rm -f "$(RELEASE_ZIP)"
	zip -r --symlinks "$(RELEASE_ZIP)" "$(BUNDLE)" -x "*.DS_Store"
	@echo "Release artifact: $(RELEASE_ZIP)"

clean:
	swift package clean
	rm -rf "$(BUNDLE)" "$(RELEASE_ZIP)"
