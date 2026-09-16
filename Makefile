APP_NAME   := Chrysalism
BUNDLE     := $(APP_NAME).app
BINARY     := .build/release/$(APP_NAME)
INSTALL_DIR := $(HOME)/Applications

.PHONY: all build app run debug install clean

all: app

build:
	swift build -c release

app: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS"
	cp "$(BINARY)" "$(BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp Info.plist "$(BUNDLE)/Contents/Info.plist"
	codesign --force --sign - "$(BUNDLE)" 2>/dev/null || true

run: app
	open "$(BUNDLE)"

debug:
	swift build && ./.build/debug/$(APP_NAME)

install: app
	rm -rf "$(INSTALL_DIR)/$(BUNDLE)"
	cp -R "$(BUNDLE)" "$(INSTALL_DIR)/"

clean:
	swift package clean
	rm -rf "$(BUNDLE)"