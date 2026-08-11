.PHONY: all build install uninstall sign verify clean

APP_PATH = $(HOME)/Applications/FlutterBuilds.app
BUILD_APP = build/FlutterBuilds.app
LSREGISTER = /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

all: build verify

build:
	@./scripts/build.sh

install: build
	@./scripts/install.sh

uninstall:
	@echo "=== Uninstalling FlutterBuilds.app ==="
	@rm -rf "$(APP_PATH)"
	@if [ -x "$(LSREGISTER)" ]; then \
		"$(LSREGISTER)" -u "$(APP_PATH)" 2>/dev/null || true; \
	fi
	@osascript -e 'tell application "System Events" to if exists login item "FlutterBuilds" then delete login item "FlutterBuilds"' 2>/dev/null || true
	@echo "Uninstalled successfully."

sign:
	@echo "=== Stripping xattr and signing build bundle ==="
	@xattr -cr $(BUILD_APP)
	@codesign --force --deep --sign - $(BUILD_APP)
	@echo "Signing complete."

verify:
	@echo "=== Verifying build artifact ==="
	@if [ ! -d "$(BUILD_APP)" ]; then \
		echo "Error: $(BUILD_APP) does not exist. Run 'make build' first." >&2; \
		exit 1; \
	fi
	@echo "1. Checking zsh syntax of src/mount.sh..."
	@zsh -n src/mount.sh
	@echo "   OK: src/mount.sh syntax is valid."
	@echo "2. Checking Info.plist validity..."
	@plutil -lint $(BUILD_APP)/Contents/Info.plist
	@echo "3. Verifying icns icon representations..."
	@TMP_ICONSET=$$(mktemp -d); \
	iconutil -c iconset $(BUILD_APP)/Contents/Resources/applet.icns -o "$$TMP_ICONSET/applet.iconset"; \
	COUNT=$$(ls -1 "$$TMP_ICONSET/applet.iconset"/*.png 2>/dev/null | wc -l | tr -d ' '); \
	rm -rf "$$TMP_ICONSET"; \
	if [ "$$COUNT" -ne 10 ]; then \
		echo "Error: applet.icns contains $$COUNT representations instead of 10!" >&2; \
		exit 1; \
	fi; \
	echo "   OK: applet.icns contains all 10 required icon representations."
	@echo "4. Verifying strict code signature..."
	@codesign --verify --strict $(BUILD_APP)
	@echo "   OK: Code signature is valid and strict."
	@echo "=== Verification SUCCESS ==="

clean:
	@rm -rf build
	@echo "Cleaned build directory."
