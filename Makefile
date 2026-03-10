APP_NAME    = KeynoteBuilder
SWIFT_FILES = $(wildcard *.swift)
APP_BUNDLE  = $(APP_NAME).app
MACOS_DIR   = $(APP_BUNDLE)/Contents/MacOS

.PHONY: build clean run

build: $(APP_BUNDLE)

$(APP_BUNDLE): $(SWIFT_FILES)
	mkdir -p $(MACOS_DIR)
	swiftc -o $(MACOS_DIR)/$(APP_NAME) $(SWIFT_FILES)
	@echo '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n\t<key>CFBundleExecutable</key>\n\t<string>$(APP_NAME)</string>\n\t<key>CFBundleIdentifier</key>\n\t<string>com.xaver.$(APP_NAME)</string>\n\t<key>CFBundleName</key>\n\t<string>$(APP_NAME)</string>\n\t<key>CFBundlePackageType</key>\n\t<string>APPL</string>\n\t<key>CFBundleShortVersionString</key>\n\t<string>1.0</string>\n</dict>\n</plist>' > $(APP_BUNDLE)/Contents/Info.plist

run: build
	open $(APP_BUNDLE)

clean:
	rm -rf $(APP_BUNDLE)
