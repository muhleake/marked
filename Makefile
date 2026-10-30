SCHEME      := Marked
DEST        := 'platform=macOS'
DERIVED     := build
APP_DEBUG   := $(DERIVED)/Build/Products/Debug/Marked.app
APP_RELEASE := $(DERIVED)/Build/Products/Release/Marked.app

.PHONY: gen build test run release install icon clean

gen:
	xcodegen generate

build: gen
	xcodebuild -scheme $(SCHEME) -destination $(DEST) -derivedDataPath $(DERIVED) build

test: gen
	xcodebuild -scheme $(SCHEME) -destination $(DEST) -derivedDataPath $(DERIVED) test

run: build
	open $(APP_DEBUG)

release: gen
	xcodebuild -scheme $(SCHEME) -destination $(DEST) -configuration Release -derivedDataPath $(DERIVED) build

install: release
	rm -rf /Applications/Marked.app
	cp -R $(APP_RELEASE) /Applications/Marked.app
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Marked.app
	@echo "Installed /Applications/Marked.app"

icon:
	swift scripts/make-icon.swift

clean:
	rm -rf $(DERIVED)
