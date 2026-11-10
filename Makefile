# Clients Browser (native macOS)
APP := build/Build/Products/Release/Clients Browser.app

.PHONY: project icon build run install clean

project:
	xcodegen generate

icon:
	swift tools/make-icon.swift ClientsBrowser/Resources/Assets.xcassets/AppIcon.appiconset

build: project
	xcodebuild -project ClientsBrowser.xcodeproj -scheme ClientsBrowser -configuration Release -derivedDataPath build build | grep -E "error:|BUILD" || true

run: project
	xcodebuild -project ClientsBrowser.xcodeproj -scheme ClientsBrowser -configuration Debug -derivedDataPath build build | grep -E "error:|BUILD" || true
	open "build/Build/Products/Debug/Clients Browser.app"

# Release build → /Applications (quits a running copy first).
install: build
	-osascript -e 'quit app "Clients Browser"'
	rm -rf "/Applications/Clients Browser.app"
	cp -R "$(APP)" /Applications/
	open "/Applications/Clients Browser.app"

clean:
	rm -rf build
